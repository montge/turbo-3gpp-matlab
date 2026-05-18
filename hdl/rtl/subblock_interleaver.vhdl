library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Sub-block interleaver address generator, TS36.212 SS5.1.4.1.1.
-- For input length D and index in {0,1,2} streams the K_Pi read pattern into
-- the NaN-left-padded sequence, bit-for-bit equal to
-- subblock_interleaver(0:D-1, idx). Emits a `filler` flag and, when not
-- filler, the original d-index.
--
-- Derived pattern (no divider): R = ceil(D/32) = (D+31)>>5, K_Pi = 32R,
-- N_D = K_Pi - D. With nested counters r0 = k mod R, c0 = floor(k/R):
--   idx 0/1 : pi_y = (r0<<5) + P[c0]
--   idx 2   : pi_y = ( (r0<<5) + P[c0] + 1 ) mod K_Pi   (single cond. sub)
--   filler  : pi_y < N_D ;  d-index = pi_y - N_D
entity subblock_interleaver is
  generic (
    W : integer := 13                                -- K_Pi <= 6176 < 2^13
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    start  : in  std_logic;                          -- latch D/idx, begin
    d_in   : in  std_logic_vector(W-1 downto 0);     -- input length D
    idx_in : in  std_logic_vector(1 downto 0);       -- sub-block index 0/1/2
    valid  : out std_logic;
    filler : out std_logic;                          -- this position is NaN pad
    idx_o  : out std_logic_vector(W-1 downto 0);     -- d-index (when not filler)
    last   : out std_logic
  );
end entity subblock_interleaver;

architecture rtl of subblock_interleaver is
  type p_arr is array (0 to 31) of integer range 0 to 31;
  constant P : p_arr := (
     0, 16,  8, 24,  4, 20, 12, 28,  2, 18, 10, 26,  6, 22, 14, 30,
     1, 17,  9, 25,  5, 21, 13, 29,  3, 19, 11, 27,  7, 23, 15, 31);

  signal Rr      : unsigned(W-1 downto 0) := (others => '0');
  signal KPi     : unsigned(W-1 downto 0) := (others => '0');
  signal ND      : unsigned(W-1 downto 0) := (others => '0');
  signal idxr    : std_logic_vector(1 downto 0) := "00";
  signal r0      : unsigned(W-1 downto 0) := (others => '0');
  signal c0      : integer range 0 to 31 := 0;
  signal kk      : unsigned(W-1 downto 0) := (others => '0');
  signal running : std_logic := '0';

  signal py0, py : unsigned(W-1 downto 0);
begin
  -- pi_y for the current (r0,c0); idx 2 adds 1 with one conditional subtract.
  py0 <= shift_left(r0, 5) + to_unsigned(P(c0), W);

  process (all)
    variable t : unsigned(W downto 0);
  begin
    if idxr = "10" then                              -- index 2
      t := ('0' & py0) + 1;
      if t >= ('0' & KPi) then
        t := t - ('0' & KPi);
      end if;
      py <= t(W-1 downto 0);
    else                                             -- index 0 or 1
      py <= py0;
    end if;
  end process;

  valid  <= running;
  last   <= '1' when (running = '1' and kk = KPi - 1) else '0';
  filler <= '1' when (running = '1' and py < ND) else '0';
  idx_o  <= std_logic_vector(py - ND) when (running = '1' and py >= ND)
            else (others => '0');

  process (clk)
    variable Rc, KPic : unsigned(W-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        running <= '0';
      elsif start = '1' then
        Rc      := shift_right(unsigned(d_in) + 31, 5);   -- ceil(D/32)
        KPic    := shift_left(Rc, 5);                     -- 32 * R
        Rr      <= Rc;
        KPi     <= KPic;
        ND      <= KPic - unsigned(d_in);
        idxr    <= idx_in;
        r0      <= (others => '0');
        c0      <= 0;
        kk      <= (others => '0');
        running <= '1';
      elsif running = '1' then
        if kk = KPi - 1 then
          running <= '0';
        else
          kk <= kk + 1;
          if r0 = Rr - 1 then
            r0 <= (others => '0');
            c0 <= c0 + 1;
          else
            r0 <= r0 + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
