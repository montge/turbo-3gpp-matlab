library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- Standalone hardware turbo-encode datapath: given only a code block and K,
-- produces the TS36.212 SS5.1.3.2 3 x (K+4) matrix. Integrates the verified
-- qpp_rom (K -> d0,step), qpp_interleaver (pi pattern) and turbo_encoder
-- (RSC + assembly) cores, all instantiated UNMODIFIED. An input block buffer
-- (1 write, 2 async read ports) supplies the natural- and interleaved-order
-- bits the encoder consumes.
--
-- FSM control signals are combinational (Mealy) so the clocked sub-cores
-- sample them aligned, exactly reproducing the stimulus that verified
-- turbo_encoder / qpp_interleaver standalone.
--
-- Protocol (testbench-driven; K-agnostic):
--   * rst='1' one cycle
--   * in_start='1' with k_in=K (one cycle)
--   * LOAD : c_in_valid='1' streaming exactly K code bits (c_in)
--   * core auto-runs: ROM lookup -> interleave+encode -> emit
--   * out_valid='1' streams the K+4 column triples; last='1' on column K+4
entity turbo_encode_top is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    in_start   : in  std_logic;
    k_in       : in  std_logic_vector(QPP_W-1 downto 0);
    c_in       : in  std_logic;
    c_in_valid : in  std_logic;
    busy       : out std_logic;
    d0_o       : out std_logic;
    d1_o       : out std_logic;
    d2_o       : out std_logic;
    out_valid  : out std_logic;
    last_o     : out std_logic
  );
end entity turbo_encode_top;

architecture rtl of turbo_encode_top is
  constant MAXK : integer := 6144;

  component qpp_rom is
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_in : in std_logic_vector(QPP_W-1 downto 0);
      done : out std_logic; supported : out std_logic;
      d0_o : out std_logic_vector(QPP_W-1 downto 0);
      step_o : out std_logic_vector(QPP_W-1 downto 0)
    );
  end component;

  component qpp_interleaver is
    generic ( W : integer := 13 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_in : in std_logic_vector(W-1 downto 0);
      d0 : in std_logic_vector(W-1 downto 0);
      step : in std_logic_vector(W-1 downto 0);
      valid : out std_logic; last : out std_logic;
      pi_o : out std_logic_vector(W-1 downto 0)
    );
  end component;

  component turbo_encoder is
    port (
      clk : in std_logic; rst : in std_logic;
      in_valid : in std_logic; in_term : in std_logic;
      c_bit : in std_logic; cprime_bit : in std_logic; emit : in std_logic;
      d0 : out std_logic; d1 : out std_logic; d2 : out std_logic;
      out_valid : out std_logic
    );
  end component;

  type buf_t is array (0 to MAXK-1) of std_logic;
  signal buf : buf_t := (others => '0');

  type state_t is (S_IDLE, S_LOAD, S_ROMSTART, S_LOOKUP, S_ENC_START,
                   S_ENC_DATA, S_ENC_TERM, S_ENC_EMIT, S_DONE);
  signal st : state_t := S_IDLE;

  signal Kr   : unsigned(QPP_W-1 downto 0) := (others => '0');
  signal widx : integer range 0 to MAXK := 0;
  signal didx : integer range 0 to MAXK := 0;
  signal tcnt : integer range 0 to 3 := 0;
  signal ecnt : integer range 0 to 4 := 0;

  signal d0c, stepc : std_logic_vector(QPP_W-1 downto 0) := (others => '0');

  signal rom_start, rom_done, rom_sup : std_logic := '0';
  signal rom_d0, rom_step : std_logic_vector(QPP_W-1 downto 0);

  signal qi_start, qi_valid, qi_last : std_logic := '0';
  signal qi_pi   : std_logic_vector(QPP_W-1 downto 0);
  signal pi_idx  : integer range 0 to MAXK-1 := 0;

  signal te_rst, te_in_valid, te_in_term, te_emit : std_logic := '0';
  signal te_cbit, te_cpbit : std_logic := '0';
  signal te_d0, te_d1, te_d2, te_ov : std_logic;
begin
  u_rom : qpp_rom
    port map (clk => clk, rst => rst, start => rom_start,
              k_in => std_logic_vector(Kr),
              done => rom_done, supported => rom_sup,
              d0_o => rom_d0, step_o => rom_step);

  u_qi : qpp_interleaver
    generic map (W => QPP_W)
    port map (clk => clk, rst => rst, start => qi_start,
              k_in => std_logic_vector(Kr), d0 => d0c, step => stepc,
              valid => qi_valid, last => qi_last, pi_o => qi_pi);

  u_te : turbo_encoder
    port map (clk => clk, rst => te_rst,
              in_valid => te_in_valid, in_term => te_in_term,
              c_bit => te_cbit, cprime_bit => te_cpbit, emit => te_emit,
              d0 => te_d0, d1 => te_d1, d2 => te_d2, out_valid => te_ov);

  pi_idx <= to_integer(unsigned(qi_pi));

  -- Combinational FSM control (Mealy).
  rom_start   <= '1' when st = S_ROMSTART  else '0';
  qi_start    <= '1' when st = S_ENC_START else '0';
  te_rst      <= '1' when (rst = '1' or st = S_ENC_START) else '0';
  te_in_valid <= '1' when (st = S_ENC_DATA or st = S_ENC_TERM) else '0';
  te_in_term  <= '1' when st = S_ENC_TERM  else '0';
  te_emit     <= '1' when st = S_ENC_EMIT  else '0';
  te_cbit     <= buf(didx)   when st = S_ENC_DATA else '0';
  te_cpbit    <= buf(pi_idx) when st = S_ENC_DATA else '0';

  d0_o      <= te_d0;
  d1_o      <= te_d1;
  d2_o      <= te_d2;
  out_valid <= te_ov when (st = S_ENC_DATA or st = S_ENC_EMIT) else '0';
  last_o    <= '1' when (st = S_ENC_EMIT and ecnt = 3 and te_ov = '1')
               else '0';
  busy      <= '0' when (st = S_IDLE or st = S_DONE) else '1';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              Kr   <= unsigned(k_in);
              widx <= 0;
              st   <= S_LOAD;
            end if;

          when S_LOAD =>
            if c_in_valid = '1' then
              buf(widx) <= c_in;
              if widx = to_integer(Kr) - 1 then
                st <= S_ROMSTART;
              else
                widx <= widx + 1;
              end if;
            end if;

          when S_ROMSTART =>
            st <= S_LOOKUP;            -- rom_start pulsed (combinational)

          when S_LOOKUP =>
            if rom_done = '1' then
              if rom_sup = '1' then
                d0c   <= rom_d0;
                stepc <= rom_step;
                st    <= S_ENC_START;
              else
                -- Unsupported K: do not encode with invalid (d0,step).
                -- Defined safe halt (busy deasserts, out_valid never
                -- asserts). Supported K (all golden vectors) is unchanged
                -- -> behaviour bit-exact.
                st <= S_DONE;
              end if;
            end if;

          when S_ENC_START =>
            didx <= 0;                 -- te_rst + qi_start pulsed
            st   <= S_ENC_DATA;

          when S_ENC_DATA =>
            if didx = to_integer(Kr) - 1 then
              tcnt <= 0;
              st   <= S_ENC_TERM;
            else
              didx <= didx + 1;
            end if;

          when S_ENC_TERM =>
            if tcnt = 2 then
              ecnt <= 0;
              st   <= S_ENC_EMIT;
            else
              tcnt <= tcnt + 1;
            end if;

          when S_ENC_EMIT =>
            if ecnt = 3 then
              st <= S_DONE;
            else
              ecnt <= ecnt + 1;
            end if;

          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
