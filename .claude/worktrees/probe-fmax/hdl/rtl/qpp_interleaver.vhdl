library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- QPP internal interleaver address generator, TS36.212 SS5.1.3.2.3.
-- Streams pi(i) = (f1*i + f2*i^2) mod K for i = 0..K-1, bit-for-bit equal to
-- internal_interleaver(0:K-1).
--
-- The quadratic's second difference is constant, giving an add-only
-- recurrence with all state < K (no wide multipliers):
--   pi_0 = 0,  d_0 = (f1+f2) mod K = d0,  step = (2*f2) mod K
--   pi_{i+1} = (pi_i + d_i) mod K
--   d_{i+1}  = (d_i + step) mod K
-- d0/step are supplied externally (pre-reduced, < K), so every sum is < 2K
-- and reduction is a single conditional subtract of K.
--
-- Values are <= 6143 (LTE max K = 6144) -> 13-bit datapath.
entity qpp_interleaver is
  generic (
    W : integer := 13
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;                       -- latch K/d0/step, begin
    k_in  : in  std_logic_vector(W-1 downto 0);  -- block length K
    d0    : in  std_logic_vector(W-1 downto 0);  -- (f1+f2) mod K
    step  : in  std_logic_vector(W-1 downto 0);  -- (2*f2)  mod K
    valid : out std_logic;                       -- pi_o valid this cycle
    last  : out std_logic;                       -- pi_o is index K-1
    pi_o  : out std_logic_vector(W-1 downto 0)
  );
end entity qpp_interleaver;

architecture rtl of qpp_interleaver is
  signal Kr      : unsigned(W-1 downto 0) := (others => '0');
  signal step_r  : unsigned(W-1 downto 0) := (others => '0');
  signal pir     : unsigned(W-1 downto 0) := (others => '0');
  signal dr      : unsigned(W-1 downto 0) := (others => '0');
  signal cnt     : unsigned(W-1 downto 0) := (others => '0');
  signal running : std_logic := '0';

  -- sum of two values < K is < 2K -> needs one extra bit; one conditional
  -- subtract of K reduces it back to [0, K).
  function reduce(a : unsigned; b : unsigned; m : unsigned) return unsigned is
    variable s : unsigned(W downto 0);
  begin
    s := ('0' & a) + ('0' & b);
    if s >= ('0' & m) then
      s := s - ('0' & m);
    end if;
    return s(W-1 downto 0);
  end function;
begin
  valid <= running;
  last  <= '1' when (running = '1' and cnt = (Kr - 1)) else '0';
  pi_o  <= std_logic_vector(pir);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        running <= '0';
      elsif start = '1' then
        Kr      <= unsigned(k_in);
        step_r  <= unsigned(step);
        pir     <= (others => '0');     -- pi_0 = 0
        dr      <= unsigned(d0);        -- d_0  = d0
        cnt     <= (others => '0');
        running <= '1';
      elsif running = '1' then
        if cnt = (Kr - 1) then
          running <= '0';               -- emitted the last index
        else
          pir <= reduce(pir, dr, Kr);
          dr  <= reduce(dr, step_r, Kr);
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
