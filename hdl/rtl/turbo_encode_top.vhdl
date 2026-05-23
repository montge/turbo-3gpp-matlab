library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- Standalone hardware turbo-encode datapath: given only a code block and K,
-- produces the TS36.212 SS5.1.3.2 3 x (K+4) matrix. Integrates the verified
-- qpp_rom (K -> d0,step), qpp_interleaver (pi pattern) and turbo_encoder
-- (RSC + assembly) cores, all instantiated UNMODIFIED. An input block buffer
-- (1 write, 2 read ports) supplies the natural- and interleaved-order bits the
-- encoder consumes.
--
-- Synthesis-hardened (DE2/Cyclone II): the input block buffer is read
-- SYNCHRONOUSLY (registered read output) on BOTH read ports -- buf(didx) and
-- buf(pi_idx) -- instead of the original combinational (async) dual read, so
-- it infers a Cyclone II M4K block RAM (simple dual-port: one write port plus
-- two registered read ports, the natural- and interleaved-order taps), WITHOUT
-- changing a single output bit (the turbo_encode_top / tx_chain_top cocotb
-- lanes stay bit-exact vs the committed golden vectors). The one-cycle read
-- latency is absorbed by a single S_ENC_PRIME prefetch beat: the read
-- addresses (didx / pi_idx) are presented one cycle ahead, their data is
-- registered into te_cbit/te_cpbit, and the encoder's data/term/emit schedule
-- runs one cycle behind the address generators -- so turbo_encoder samples the
-- same (c, c_prime) bit pair on the same relative beat as before.
--
-- FSM control signals are otherwise combinational (Mealy) so the clocked
-- sub-cores sample them aligned, exactly reproducing the stimulus that
-- verified turbo_encoder / qpp_interleaver standalone.
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

  -- Synchronous-read registers for the two read ports of buf (registered read
  -- output -> M4K simple-dual-port). cbit_r/cpbit_r hold buf(didx)/buf(pi_idx)
  -- for the addresses presented (combinationally) on the previous clock edge.
  signal cbit_r, cpbit_r : std_logic := '0';

  type state_t is (S_IDLE, S_LOAD, S_ROMSTART, S_LOOKUP, S_ENC_START,
                   S_ENC_PRIME, S_ENC_DATA, S_ENC_TERM, S_ENC_EMIT, S_DONE);
  signal st : state_t := S_IDLE;

  signal Kr   : unsigned(QPP_W-1 downto 0) := (others => '0');
  signal widx : integer range 0 to MAXK := 0;
  signal didx : integer range 0 to MAXK := 0;  -- natural read-address index
  signal cdc  : integer range 0 to MAXK := 0;  -- encoder data-bit consume count
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
  -- Encoder is fed the REGISTERED buffer reads (data for the addresses issued
  -- on the previous edge), so the data/term/emit schedule trails the address
  -- generators by the single S_ENC_PRIME beat. Same bit pair, same beat.
  te_cbit     <= cbit_r  when st = S_ENC_DATA else '0';
  te_cpbit    <= cpbit_r when st = S_ENC_DATA else '0';

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
      -- Synchronous read of both buf ports: the read output is registered, so
      -- the data for the addresses presented at this edge (didx / pi_idx)
      -- appears next edge (M4K simple-dual-port). The encoder consumes these
      -- one beat later, in S_ENC_DATA.
      cbit_r  <= buf(didx);
      cpbit_r <= buf(pi_idx);

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
            cdc  <= 0;
            st   <= S_ENC_PRIME;

          -- Prefetch beat: this cycle presents address index 0 (didx=0,
          -- pi_idx=pi(0)); its data lands in cbit_r/cpbit_r at the edge into
          -- S_ENC_DATA. te_in_valid is low here (no encode step yet), so no
          -- body column is emitted. Advance the address generators by one so
          -- S_ENC_DATA always presents the index whose data feeds the NEXT
          -- consume, absorbing the one-cycle read latency.
          when S_ENC_PRIME =>
            if to_integer(Kr) > 1 then
              didx <= 1;
            end if;
            st <= S_ENC_DATA;

          -- Consume K registered data pairs (cdc = 0..K-1). The address index
          -- didx runs one ahead (clamped at K-1, harmless+masked once the last
          -- pair is captured); cdc gates the exit so exactly K bits encode.
          when S_ENC_DATA =>
            if cdc = to_integer(Kr) - 1 then
              tcnt <= 0;
              st   <= S_ENC_TERM;
            else
              cdc <= cdc + 1;
              if didx < to_integer(Kr) - 1 then
                didx <= didx + 1;
              end if;
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
