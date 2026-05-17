library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Integrated rate matching, TS36.212 SS5.1.4.1. Bit-for-bit equivalent of
-- rate_matching(d, N_ref, I_LBRM, rv_idx, E):
--   v = [subblock_interleaver(d(1,:),0);
--        subblock_interleaver(d(2,:),1);
--        subblock_interleaver(d(3,:),2)];
--   e = circular_buffer(v, N_ref, I_LBRM, rv_idx, E);
--
-- Wires three UNMODIFIED subblock_interleaver instances (idx 0/1/2, run in
-- lockstep so element k of all three is presented on the same cycle) and one
-- UNMODIFIED circular_buffer. Only the orchestration FSM + the 3xD input
-- buffer are new. Sim-first (sub-cores keep their arithmetic).
entity rate_matching_top is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    in_start : in  std_logic;                       -- latch D/params, begin
    d_len    : in  std_logic_vector(12 downto 0);   -- D (= K+4 in the chain)
    n_ref_in : in  std_logic_vector(15 downto 0);
    i_lbrm   : in  std_logic;
    rv_in    : in  std_logic_vector(1 downto 0);
    e_in     : in  std_logic_vector(15 downto 0);
    d_valid  : in  std_logic;                       -- a d column this cycle
    d1_in    : in  std_logic;                       -- d(1,k)
    d2_in    : in  std_logic;                       -- d(2,k)
    d3_in    : in  std_logic;                       -- d(3,k)
    out_valid: out std_logic;                        -- e_bit valid this cycle
    e_bit    : out std_logic;
    last     : out std_logic
  );
end entity rate_matching_top;

architecture rtl of rate_matching_top is
  constant DMAX : integer := 6148;

  component subblock_interleaver is
    generic ( W : integer := 13 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      d_in : in std_logic_vector(W-1 downto 0);
      idx_in : in std_logic_vector(1 downto 0);
      valid : out std_logic; filler : out std_logic;
      idx_o : out std_logic_vector(W-1 downto 0);
      last : out std_logic
    );
  end component;

  component circular_buffer is
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_pi_in : in std_logic_vector(13 downto 0);
      n_ref_in : in std_logic_vector(15 downto 0);
      i_lbrm : in std_logic;
      rv_in : in std_logic_vector(1 downto 0);
      e_in : in std_logic_vector(15 downto 0);
      v_valid : in std_logic;
      v1_bit : in std_logic; v1_fill : in std_logic;
      v2_bit : in std_logic; v2_fill : in std_logic;
      v3_bit : in std_logic; v3_fill : in std_logic;
      out_valid : out std_logic; e_bit : out std_logic; last : out std_logic
    );
  end component;

  type bit_arr is array (0 to DMAX-1) of std_logic;
  signal d1buf, d2buf, d3buf : bit_arr := (others => '0');

  type state_t is (S_IDLE, S_LOADD, S_INIT, S_STREAM, S_WAIT, S_DONE);
  signal st : state_t := S_IDLE;

  signal Dr   : unsigned(12 downto 0) := (others => '0');
  signal KPi  : unsigned(13 downto 0) := (others => '0');
  signal widx : integer range 0 to DMAX := 0;

  signal sub_start, cb_start, cb_vv : std_logic := '0';

  -- subblock instances (0/1/2)
  signal s0_v, s0_f, s0_l : std_logic;
  signal s1_v, s1_f, s1_l : std_logic;
  signal s2_v, s2_f, s2_l : std_logic;
  signal s0_idx, s1_idx, s2_idx : std_logic_vector(12 downto 0);

  signal v1b, v2b, v3b : std_logic;
  signal cb_ov, cb_eb, cb_lst : std_logic;
begin
  i_sub0 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "00",
              valid => s0_v, filler => s0_f, idx_o => s0_idx, last => s0_l);
  i_sub1 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "01",
              valid => s1_v, filler => s1_f, idx_o => s1_idx, last => s1_l);
  i_sub2 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "10",
              valid => s2_v, filler => s2_f, idx_o => s2_idx, last => s2_l);

  -- v(r,k) = filler ? 0 : d_r[idx_o_r]   (async read of the input buffers)
  v1b <= '0' when s0_f = '1' else d1buf(to_integer(unsigned(s0_idx)));
  v2b <= '0' when s1_f = '1' else d2buf(to_integer(unsigned(s1_idx)));
  v3b <= '0' when s2_f = '1' else d3buf(to_integer(unsigned(s2_idx)));

  i_cb : circular_buffer
    port map (clk => clk, rst => rst, start => cb_start,
              k_pi_in => std_logic_vector(KPi),
              n_ref_in => n_ref_in, i_lbrm => i_lbrm,
              rv_in => rv_in, e_in => e_in,
              v_valid => cb_vv,
              v1_bit => v1b, v1_fill => s0_f,
              v2_bit => v2b, v2_fill => s1_f,
              v3_bit => v3b, v3_fill => s2_f,
              out_valid => cb_ov, e_bit => cb_eb, last => cb_lst);

  -- Combinational FSM control.
  sub_start <= '1' when st = S_INIT else '0';
  cb_start  <= '1' when st = S_INIT else '0';
  cb_vv     <= '1' when st = S_STREAM else '0';

  out_valid <= cb_ov when (st = S_WAIT) else '0';
  e_bit     <= cb_eb;
  last      <= cb_lst when (st = S_WAIT) else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              Dr   <= unsigned(d_len);
              -- K_Pi = 32 * ceil(D/32) = ((D+31)>>5)<<5
              KPi  <= shift_left(
                        resize(shift_right(unsigned(d_len) + 31, 5), 14), 5);
              widx <= 0;
              st   <= S_LOADD;
            end if;

          when S_LOADD =>
            if d_valid = '1' then
              d1buf(widx) <= d1_in;
              d2buf(widx) <= d2_in;
              d3buf(widx) <= d3_in;
              if widx = to_integer(Dr) - 1 then
                st <= S_INIT;
              else
                widx <= widx + 1;
              end if;
            end if;

          when S_INIT =>
            st <= S_STREAM;            -- sub_start + cb_start pulsed

          when S_STREAM =>
            if s0_l = '1' then         -- final sub-block element (K_Pi-1)
              st <= S_WAIT;
            end if;

          when S_WAIT =>
            if cb_lst = '1' then
              st <= S_DONE;
            end if;

          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
