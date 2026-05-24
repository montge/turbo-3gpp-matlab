library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- ===========================================================================
-- rx_chain_top : complete hardware LTE receive chain -- soft de-rate-matching
-- -> turbo decode. The P4 mirror (in reverse) of tx_chain_top
-- (turbo_encode_top -> rate_matching_top).
--
-- Given a length-E stream of received channel LLRs and the block params
-- (K, F_r, N_ref, I_LBRM, rv_idx, E), produces the K decoded hard bits, equal
-- to the float RX path:
--   d_a = <de-rate-match>(e, ...)             % turbo_decoding_chain.m 86-93
--   c   = turbo_decoder(d_a, ...)             % the iterative Max-Log-MAP loop
--
-- Wires the new de_rate_matching_top directly into the UNMODIFIED
-- turbo_decoder_top: de_rate_matching_top emits the 3x(K+4) soft d_a matrix
-- column-major on da_valid / da{1,2,3}_o (W_EXT signed), which is EXACTLY the
-- decoder's load port (da_valid / da{1,2,3}_in, W_EXT wide -- see the
-- turbo_decoder_top entity header LOAD protocol). Only the start-pulse FSM and
-- the LLR pass-through are new; both sub-cores keep their own arithmetic.
--
-- The decoder is started with the SAME in_start pulse as the de-rate-match:
-- turbo_decoder_top latches K and then sits in its S_LOAD_D state waiting for
-- da_valid, which de_rate_matching_top only raises after its map-build /
-- soft scatter-accumulate / scatter / filler phases. So the long de-rate-match
-- prelude is naturally absorbed -- the first da_valid beat is the first column
-- the decoder consumes, in order, with no handshake needed beyond da_valid.
--
-- The received LLR stream is a pull interface: de_rate_matching_top raises
-- e_req when it wants the next LLR e_soft(k) (in TX read order); rx_chain_top
-- forwards e_req to the caller and passes e_soft straight through. The caller
-- presents the W_LLR-quantised channel LLRs (the demapper grid).
--
-- BIT-EXACT / FORMAT CONTRACT: see de_rate_matching_top.vhdl (oracle
-- scripts/fixedpoint_de_rate_matching.m) for the de-rate-match, and
-- turbo_decoder_top.vhdl (oracle scripts/fixedpoint_turbo_decoder.m) for the
-- decode loop. The W_EXT=12 (Q7.4) d_a word is the shared exchange grid; the
-- +inf filler sentinel MAX_SENT and 0 erasure flow straight into the decoder
-- load de-mux unchanged. Scope: single code block (C=1), plain decoder, single
-- transmission (design.md Non-Goals).
-- ===========================================================================
entity rx_chain_top is
  generic (
    -- Buffer-depth maxima threaded to de_rate_matching_top (DMAX, KW_MAX) and
    -- turbo_decoder_top (K_MAX). Default to the TS36.212 maxima; board demos
    -- override them small (sized for their K) so the design fits a small FPGA.
    DMAX           : integer := 6148;
    KW_MAX         : integer := 3 * 6176;              -- 18528
    K_MAX          : integer := 6144;
    W_LLR          : integer := 8;                     -- channel LLR (Q3.4)
    W_DRM          : integer := 16;                    -- soft accumulator (Q11.4)
    W_EXT          : integer := 12;                    -- decoder load word (Q7.4)
    MAX_ITERATIONS : integer := 8                      -- decoder H = 2*this
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    in_start  : in  std_logic;                         -- latch params, begin
    k_in      : in  std_logic_vector(12 downto 0);     -- block length K
    f_r_in    : in  std_logic_vector(12 downto 0);     -- filler count F_r
    n_ref_in  : in  std_logic_vector(15 downto 0);
    i_lbrm    : in  std_logic;
    rv_in     : in  std_logic_vector(1 downto 0);
    e_in      : in  std_logic_vector(15 downto 0);     -- received length E
    -- received soft LLR pull interface (W_LLR signed code).
    e_soft_in : in  std_logic_vector(W_LLR-1 downto 0);
    e_req     : out std_logic;                         -- pull next LLR
    -- decoded hard bits, c[0] first.
    out_valid : out std_logic;
    out_last  : out std_logic;
    c_out     : out std_logic;
    busy      : out std_logic;
    done      : out std_logic                          -- one-cycle pulse
  );
end entity rx_chain_top;

architecture rtl of rx_chain_top is
  component de_rate_matching_top is
    generic (
      DMAX : integer := 6148; KW_MAX : integer := 3 * 6176;
      W_LLR : integer := 8; W_DRM : integer := 16; W_EXT : integer := 12
    );
    port (
      clk : in std_logic; rst : in std_logic; in_start : in std_logic;
      k_in : in std_logic_vector(12 downto 0);
      f_r_in : in std_logic_vector(12 downto 0);
      n_ref_in : in std_logic_vector(15 downto 0);
      i_lbrm : in std_logic;
      rv_in : in std_logic_vector(1 downto 0);
      e_in : in std_logic_vector(15 downto 0);
      e_soft_in : in std_logic_vector(W_LLR-1 downto 0);
      e_req : out std_logic;
      da_valid : out std_logic;
      da1_o : out std_logic_vector(W_EXT-1 downto 0);
      da2_o : out std_logic_vector(W_EXT-1 downto 0);
      da3_o : out std_logic_vector(W_EXT-1 downto 0);
      da_last : out std_logic;
      busy : out std_logic; done : out std_logic
    );
  end component;

  component turbo_decoder_top is
    generic (
      W_IN : integer := 9; W_GAMMA : integer := 10; W_AB : integer := 15;
      W_DELTA : integer := 17; W_XE : integer := 18;
      W_EXT : integer := 12; W_ACC : integer := 14;
      W_K : integer := 13; K_MAX : integer := 6144;
      MAX_ITERATIONS : integer := 8
    );
    port (
      clk : in std_logic; rst : in std_logic; in_start : in std_logic;
      k_in : in std_logic_vector(W_K-1 downto 0);
      da_valid : in std_logic;
      da1_in : in std_logic_vector(W_EXT-1 downto 0);
      da2_in : in std_logic_vector(W_EXT-1 downto 0);
      da3_in : in std_logic_vector(W_EXT-1 downto 0);
      out_valid : out std_logic; out_last : out std_logic; c_out : out std_logic;
      busy : out std_logic; done : out std_logic
    );
  end component;

  type state_t is (S_IDLE, S_START, S_RUN, S_DONE);
  signal st : state_t := S_IDLE;

  signal drm_start, dec_start : std_logic := '0';
  -- de-rate-match -> decoder load bus.
  signal drm_dav, drm_dal, drm_busy, drm_done : std_logic;
  signal drm_da1, drm_da2, drm_da3 : std_logic_vector(W_EXT-1 downto 0);
  signal drm_ereq : std_logic;
  -- decoder outputs.
  signal dec_ov, dec_ol, dec_cb, dec_busy, dec_done : std_logic;

  signal k_latch   : std_logic_vector(12 downto 0) := (others => '0');
  signal f_r_latch : std_logic_vector(12 downto 0) := (others => '0');
  signal nref_latch: std_logic_vector(15 downto 0) := (others => '0');
  signal lbrm_latch: std_logic := '0';
  signal rv_latch  : std_logic_vector(1 downto 0) := "00";
  signal e_latch   : std_logic_vector(15 downto 0) := (others => '0');
begin
  i_drm : de_rate_matching_top
    generic map (DMAX => DMAX, KW_MAX => KW_MAX,
                 W_LLR => W_LLR, W_DRM => W_DRM, W_EXT => W_EXT)
    port map (clk => clk, rst => rst, in_start => drm_start,
              k_in => k_latch, f_r_in => f_r_latch,
              n_ref_in => nref_latch, i_lbrm => lbrm_latch,
              rv_in => rv_latch, e_in => e_latch,
              e_soft_in => e_soft_in, e_req => drm_ereq,
              da_valid => drm_dav,
              da1_o => drm_da1, da2_o => drm_da2, da3_o => drm_da3,
              da_last => drm_dal, busy => drm_busy, done => drm_done);

  i_dec : turbo_decoder_top
    generic map (W_EXT => W_EXT, K_MAX => K_MAX,
                 MAX_ITERATIONS => MAX_ITERATIONS)
    port map (clk => clk, rst => rst, in_start => dec_start,
              k_in => k_latch,
              da_valid => drm_dav,              -- de-rate-match column stream
              da1_in => drm_da1, da2_in => drm_da2, da3_in => drm_da3,
              out_valid => dec_ov, out_last => dec_ol, c_out => dec_cb,
              busy => dec_busy, done => dec_done);

  drm_start <= '1' when st = S_START else '0';
  dec_start <= '1' when st = S_START else '0';

  -- LLR pull straight through (only meaningful while the de-rate-match runs).
  e_req <= drm_ereq when (st = S_RUN) else '0';

  out_valid <= dec_ov when (st = S_RUN) else '0';
  out_last  <= dec_ol when (st = S_RUN) else '0';
  c_out     <= dec_cb;
  busy      <= '1' when (st = S_START or st = S_RUN) else '0';
  done      <= dec_done when (st = S_RUN) else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              k_latch    <= k_in;
              f_r_latch  <= f_r_in;
              nref_latch <= n_ref_in;
              lbrm_latch <= i_lbrm;
              rv_latch   <= rv_in;
              e_latch    <= e_in;
              st         <= S_START;
            end if;
          when S_START =>
            st <= S_RUN;             -- drm_start + dec_start pulsed
          when S_RUN =>
            if dec_done = '1' then
              st <= S_DONE;
            end if;
          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
