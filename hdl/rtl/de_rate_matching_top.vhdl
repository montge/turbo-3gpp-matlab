library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- de_rate_matching_top : integrated (soft) de-rate-matching, TS36.212
-- SS5.1.4.1, RECEIVE side. The P4 (RX-chain) soft mirror of
-- rate_matching_top.vhdl. It turns a length-E stream of received channel LLRs
-- back into the 3x(K+4) soft d_a matrix the turbo decoder loads.
--
-- TX (rate_matching_top):  d --subblock_interleaver x3--> v --circular_buffer
--                          (gather/read E bits)--> e
-- RX (this core, inverse): e --de_circular_buffer (scatter-accumulate into the
--                          soft w)--> w_soft --inverse subblock-interleave
--                          (scatter w_soft -> d_a)--> d_a (+inf filler / 0
--                          erasure, saturated to W_EXT).
--
-- ---------------------------------------------------------------------------
-- BIT-EXACT CONTRACT (oracle = scripts/fixedpoint_de_rate_matching.m; the
-- cocotb lane, change add-fpga-rx-chain-integration stage 4, asserts this
-- core's d_a output bit-for-bit vs vectors derived from the oracle). The
-- oracle factors the inline float de-rate-match (turbo_decoding_chain.m lines
-- 86-93) and adds the fixed-point quantisation / saturating soft-combine:
--   d_vec = zeros(1,3*D); for k: d_vec(pi(k)+1) += e(k);    % SCATTER-ACCUMULATE
--   d = reshape(d_vec,3,D); d(1:2,1:F_r) = NaN;             % filler -> +inf
-- where pi is the SAME length-E permutation the TX rate_matching produced.
--
-- This core reproduces that EXACTLY, reusing the TX cores' addressing in the
-- inverse direction:
--   (a) INVERSE SUBBLOCK-INTERLEAVE (inverts subblock_interleaver x3). The
--       UNMODIFIED subblock_interleaver is a direction-agnostic address+filler
--       generator: for D=K+4 and idx 0/1/2 it emits, per position col=0..K_Pi-1,
--       (filler, d-index). The v element v(row,col) holds d(row, d-index) when
--       not filler. We build a per-w-position MAP: for each col, the systematic
--       (idx0->w_sys[col]), even-parity (idx1->w_ev[col]) and odd-parity
--       (idx2->w_od[col]) banks each record (filler, target) where target is
--       the COLUMN-MAJOR d_vec index of d(row, d-index): for 1-based row r and
--       0-based d-index j, target = 3*j + (r-1). The fillers also drive the
--       circular read-skip. Building the map is the EXACT inverse of how
--       rate_matching_top assembles v from the three subblock streams.
--   (b) INVERSE CIRCULAR BUFFER (inverts circular_buffer, soft). The standalone
--       de_circular_buffer walks the IDENTICAL k_0/N_cb/dummy-skip read order
--       and, per received LLR, accumulates (saturating) w_soft(pos) += e_soft.
--       Wrap revisits (E>N_cb) soft-combine; never-visited positions stay 0
--       (erasure). The filler skip uses the map's per-position fill flags
--       (the TX while-loop `~isnan(w(...))` guard).
--   (c) SCATTER w_soft -> d_a. After the accumulate, walk every w position
--       (sys/ev/od banks, col 0..K_Pi-1); for each NON-filler position read the
--       soft w word and its map target, and write d_a_dvec(target) =
--       sat_clip(w_soft, W_EXT). Erasure (untransmitted) positions are never
--       written -> stay 0; filler positions carry no d-element and are dropped.
--   (d) FILLER. d_a(1,1:F_r) and d_a(2,1:F_r) -> the +inf sentinel MAX_SENT
--       (the float d(1:2,1:F_r)=NaN, which the decoder maps to +inf). In
--       column-major d_vec terms: indices 3*c+0 (row1) and 3*c+1 (row2) for
--       c=0..F_r-1. (Row 3 is NOT masked, matching the float.) Done AFTER the
--       W_EXT saturation so the token is exactly MAX_SENT.
--   (e) OUTPUT. Stream the 3x(K+4) d_a matrix COLUMN-MAJOR on da_valid, each
--       beat presenting d_a(1)/d_a(2)/d_a(3) (= d_vec[3c], [3c+1], [3c+2]) on
--       da1_o/da2_o/da3_o (W_EXT signed) -- the EXACT turbo_decoder_top load
--       format.
--
-- PINNED FIXED-POINT (design.md Decision 3):
--   W_LLR = 8  (Q3.4) received channel-LLR input word (the demapper grid).
--   W_DRM = 16 (Q11.4) soft-combine accumulator (saturating; ~64x headroom).
--   W_EXT = 12 (Q7.4) decoder load word; the W_DRM accumulator is saturated to
--               W_EXT at the output (inherited P2, unchanged).
--   MAX_SENT = +2047 (the W_EXT +inf token; P1 sentinel mapped onto the grid).
--   Erasure = 0 (the zero-init of the accumulate; no new token).
-- F_in = 4 is shared across all grids, so W_LLR->W_DRM and W_DRM->W_EXT are
-- pure width/saturate boundaries (no rescale): an incoming W_LLR LLR is
-- sign-extended to the W_DRM accumulator grid directly.
--
-- M4K-FRIENDLY STORAGE (the proven circular_buffer/rate_matching_top recipe):
-- the map banks (target + 1-bit fill, sys/ev/od) and the d_a output buffer are
-- single-write-port arrays whose writes are at the top level of a dedicated
-- unconditional clocked memory process (lifted out of the reset/case nest);
-- reads are registered (synchronous). The soft w banks live in
-- de_circular_buffer (M4K there). ramstyle="M4K" pins the intent so a board
-- build fits, mirroring the TX tops.
-- ===========================================================================
entity de_rate_matching_top is
  generic (
    -- Max input length D the map / d_a buffers are sized for (D = K+4, max
    -- 6148). Board demos override small. Mirrors rate_matching_top DMAX.
    DMAX   : integer := 6148;
    -- Max circular-buffer depth K_w (= 3*K_Pi), threaded to de_circular_buffer.
    KW_MAX : integer := 3 * 6176;                      -- 18528
    W_LLR  : integer := 8;                             -- channel LLR input (Q3.4)
    W_DRM  : integer := 16;                            -- soft accumulator (Q11.4)
    W_EXT  : integer := 12                             -- decoder load word (Q7.4)
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    in_start : in  std_logic;                          -- latch params, begin
    k_in     : in  std_logic_vector(12 downto 0);      -- block length K
    f_r_in   : in  std_logic_vector(12 downto 0);      -- filler count F_r
    n_ref_in : in  std_logic_vector(15 downto 0);
    i_lbrm   : in  std_logic;
    rv_in    : in  std_logic_vector(1 downto 0);
    e_in     : in  std_logic_vector(15 downto 0);      -- received length E
    -- Received soft LLR stream: present e_soft for the requested index when
    -- e_req pulses (the core pulls them in TX read order). W_LLR signed code.
    e_soft_in: in  std_logic_vector(W_LLR-1 downto 0);
    e_req    : out std_logic;                          -- pull next LLR
    -- d_a output: K+4 column beats, column-major, W_EXT signed codes.
    da_valid : out std_logic;
    da1_o    : out std_logic_vector(W_EXT-1 downto 0); -- d_a(1,col)
    da2_o    : out std_logic_vector(W_EXT-1 downto 0); -- d_a(2,col)
    da3_o    : out std_logic_vector(W_EXT-1 downto 0); -- d_a(3,col)
    da_last  : out std_logic;
    busy     : out std_logic;
    done     : out std_logic                           -- one-cycle pulse
  );
end entity de_rate_matching_top;

architecture rtl of de_rate_matching_top is
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

  component de_circular_buffer is
    generic ( KW_MAX : integer := 3 * 6176; W_DRM : integer := 16 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_pi_in : in std_logic_vector(13 downto 0);
      n_ref_in : in std_logic_vector(15 downto 0);
      i_lbrm : in std_logic;
      rv_in : in std_logic_vector(1 downto 0);
      e_in : in std_logic_vector(15 downto 0);
      fsys_in : in std_logic; fev_in : in std_logic; fod_in : in std_logic;
      f_col_o : out std_logic_vector(13 downto 0);
      e_soft_in : in std_logic_vector(W_DRM-1 downto 0);
      e_req : out std_logic;
      rb_addr : in std_logic_vector(13 downto 0);
      rb_sys_o : out std_logic_vector(W_DRM-1 downto 0);
      rb_ev_o : out std_logic_vector(W_DRM-1 downto 0);
      rb_od_o : out std_logic_vector(W_DRM-1 downto 0);
      busy : out std_logic; done : out std_logic
    );
  end component;

  constant BANK_MAX : integer := KW_MAX / 3;           -- max per-bank K_Pi
  constant DVEC_MAX : integer := 3 * DMAX;             -- max 3*(K+4) d_vec len
  constant EXT_MIN  : integer := -(2**(W_EXT-1));
  constant EXT_MAX  : integer :=  (2**(W_EXT-1)) - 1;
  constant MAX_SENT : integer := EXT_MAX;              -- +inf filler token

  -- ---- Per-w-position MAP banks (built from the 3 subblock streams). Each
  -- holds, per column 0..K_Pi-1, the target d_vec index and a filler flag.
  -- Single write port each; M4K-friendly (write lifted to mem_proc, sync read).
  type tgt_arr  is array (0 to BANK_MAX-1) of integer range 0 to DVEC_MAX-1;
  type fill_arr is array (0 to BANK_MAX-1) of std_logic;
  signal map_sys_t, map_ev_t, map_od_t : tgt_arr := (others => 0);
  signal map_sys_f, map_ev_f, map_od_f : fill_arr := (others => '0');
  attribute ramstyle : string;
  attribute ramstyle of map_sys_t : signal is "M4K";
  attribute ramstyle of map_ev_t  : signal is "M4K";
  attribute ramstyle of map_od_t  : signal is "M4K";

  -- ---- d_a output buffer, column-major d_vec (length 3*(K+4)). Single write
  -- port (scatter + filler), registered read (output stream). M4K-friendly.
  type dvec_arr is array (0 to DVEC_MAX-1) of integer;
  signal d_a_dvec : dvec_arr := (others => 0);
  attribute ramstyle of d_a_dvec : signal is "M4K";

  -- Map write port.
  signal mw_en   : std_logic := '0';
  signal mw_col  : integer range 0 to BANK_MAX-1 := 0;
  signal mw_sys_t, mw_ev_t, mw_od_t : integer range 0 to DVEC_MAX-1 := 0;
  signal mw_sys_f, mw_ev_f, mw_od_f : std_logic := '0';
  -- Map read port (registered): filler fetch for de_circular_buffer (f_col)
  -- and the scatter target/fill fetch (sc_col).
  signal mr_col  : integer range 0 to BANK_MAX-1 := 0;
  signal mr_sys_t, mr_ev_t, mr_od_t : integer range 0 to DVEC_MAX-1 := 0;
  signal mr_sys_f, mr_ev_f, mr_od_f : std_logic := '0';

  -- d_a buffer write port.
  signal dw_en   : std_logic := '0';
  signal dw_addr : integer range 0 to DVEC_MAX-1 := 0;
  signal dw_data : integer := 0;
  -- d_a buffer read port (registered): output stream.
  signal dr_addr : integer range 0 to DVEC_MAX-1 := 0;
  signal dr_data : integer := 0;

  type state_t is (
    S_IDLE, S_MAP_START, S_MAP, S_DCB_START, S_DCB,
    S_SC_PRIME, S_SC, S_FILL, S_OUT_PRIME, S_OUT, S_DONE);
  signal st : state_t := S_IDLE;

  signal Kr   : integer range 0 to 6144 := 0;
  signal Dr   : integer range 0 to DMAX := 0;          -- D = K+4
  signal Fr   : integer range 0 to 6144 := 0;
  signal KPi  : integer range 0 to 6176 := 0;          -- 32*ceil(D/32)

  -- subblock instances (built once into the map).
  signal sub_start : std_logic := '0';
  signal s0_v, s0_f, s0_l : std_logic;
  signal s1_v, s1_f, s1_l : std_logic;
  signal s2_v, s2_f, s2_l : std_logic;
  signal s0_idx, s1_idx, s2_idx : std_logic_vector(12 downto 0);
  signal map_col : integer range 0 to BANK_MAX := 0;   -- subblock position k

  -- de_circular_buffer wiring.
  signal dcb_start : std_logic := '0';
  signal dcb_fcol  : std_logic_vector(13 downto 0);
  signal dcb_ereq  : std_logic;
  signal dcb_esoft : std_logic_vector(W_DRM-1 downto 0);
  signal dcb_rb_addr : std_logic_vector(13 downto 0) := (others => '0');
  signal dcb_rb_sys, dcb_rb_ev, dcb_rb_od : std_logic_vector(W_DRM-1 downto 0);
  signal dcb_busy, dcb_done : std_logic;

  -- scatter sweep.
  signal sc_col : integer range 0 to BANK_MAX := 0;    -- w column being scattered
  signal sc_bank: integer range 0 to 2 := 0;           -- 0=sys 1=ev 2=od
  signal fill_idx : integer range 0 to 6144 := 0;      -- filler write sweep
  signal fill_lo  : std_logic := '0';                  -- low/high of the F_r pair
  signal out_col  : integer range 0 to DMAX := 0;      -- output column index
  signal out_sub  : integer range 0 to 2 := 0;         -- which of the 3 rows

  -- output regs (collect a column's 3 words then beat).
  signal da1r, da2r, da3r : integer := 0;
  signal dav, dal, bsy, dn : std_logic := '0';

  function sat_clip(x, lo, hi : integer) return integer is
  begin
    if x > hi then return hi;
    elsif x < lo then return lo;
    else return x; end if;
  end function;
begin
  i_sub0 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(to_unsigned(Dr, 13)), idx_in => "00",
              valid => s0_v, filler => s0_f, idx_o => s0_idx, last => s0_l);
  i_sub1 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(to_unsigned(Dr, 13)), idx_in => "01",
              valid => s1_v, filler => s1_f, idx_o => s1_idx, last => s1_l);
  i_sub2 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(to_unsigned(Dr, 13)), idx_in => "10",
              valid => s2_v, filler => s2_f, idx_o => s2_idx, last => s2_l);

  -- e_soft to de_circular_buffer: sign-extend the W_LLR input to the W_DRM grid
  -- (F_in shared -> pure width extend, no rescale).
  dcb_esoft <= std_logic_vector(resize(signed(e_soft_in), W_DRM));

  i_dcb : de_circular_buffer
    generic map (KW_MAX => KW_MAX, W_DRM => W_DRM)
    port map (clk => clk, rst => rst, start => dcb_start,
              k_pi_in => std_logic_vector(to_unsigned(KPi, 14)),
              n_ref_in => n_ref_in, i_lbrm => i_lbrm,
              rv_in => rv_in, e_in => e_in,
              -- filler flags for the position de_circular_buffer is visiting:
              -- it presents f_col_o = the bank column; we return the registered
              -- map fill flag for each bank (it selects by its own cur_bank).
              fsys_in => mr_sys_f, fev_in => mr_ev_f, fod_in => mr_od_f,
              f_col_o => dcb_fcol,
              e_soft_in => dcb_esoft, e_req => dcb_ereq,
              rb_addr => dcb_rb_addr,
              rb_sys_o => dcb_rb_sys, rb_ev_o => dcb_rb_ev, rb_od_o => dcb_rb_od,
              busy => dcb_busy, done => dcb_done);

  sub_start <= '1' when st = S_MAP_START else '0';
  dcb_start <= '1' when st = S_DCB_START else '0';

  -- e_req to the caller is de_circular_buffer's pull (only meaningful in S_DCB).
  e_req <= dcb_ereq when st = S_DCB else '0';

  da_valid <= dav;
  da_last  <= dal;
  da1_o <= std_logic_vector(to_signed(da1r, W_EXT));
  da2_o <= std_logic_vector(to_signed(da2r, W_EXT));
  da3_o <= std_logic_vector(to_signed(da3r, W_EXT));
  busy  <= bsy;
  done  <= dn;

  -- ---- Map-bank read address: in S_DCB the filler fetch uses de_circular_
  -- buffer's f_col_o; in the scatter phase it uses sc_col. ----
  mr_col <= to_integer(unsigned(dcb_fcol)) when st = S_DCB
            else sc_col when sc_col < BANK_MAX else 0;

  -- ---- de_circular_buffer read-back address = the scatter column. ----
  dcb_rb_addr <= std_logic_vector(to_unsigned(sc_col, 14))
                 when sc_col < BANK_MAX else (others => '0');

  -- ---- Dedicated memory process: map + d_a writes (lifted, single port),
  -- registered reads. M4K-inferable. ----
  mem_proc : process (clk)
  begin
    if rising_edge(clk) then
      -- map writes (one per bank, same column).
      if mw_en = '1' then
        map_sys_t(mw_col) <= mw_sys_t;  map_sys_f(mw_col) <= mw_sys_f;
        map_ev_t(mw_col)  <= mw_ev_t;   map_ev_f(mw_col)  <= mw_ev_f;
        map_od_t(mw_col)  <= mw_od_t;   map_od_f(mw_col)  <= mw_od_f;
      end if;
      -- map registered reads (all three banks at mr_col).
      mr_sys_t <= map_sys_t(mr_col);  mr_sys_f <= map_sys_f(mr_col);
      mr_ev_t  <= map_ev_t(mr_col);   mr_ev_f  <= map_ev_f(mr_col);
      mr_od_t  <= map_od_t(mr_col);   mr_od_f  <= map_od_f(mr_col);
      -- d_a buffer write (scatter / filler) + registered read (output).
      if dw_en = '1' then
        d_a_dvec(dw_addr) <= dw_data;
      end if;
      dr_data <= d_a_dvec(dr_addr);
    end if;
  end process mem_proc;

  process (clk)
    variable t : integer;
    variable wsoft : integer;
    variable isfill : std_logic;
  begin
    if rising_edge(clk) then
      mw_en <= '0';
      dw_en <= '0';
      dav   <= '0';
      dal   <= '0';
      dn    <= '0';

      if rst = '1' then
        st  <= S_IDLE;
        bsy <= '0';
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              if unsigned(k_in) = 0
                 or (to_integer(unsigned(k_in)) + 4) > DMAX then
                st <= S_DONE;          -- out-of-contract safe abort
              else
                Kr  <= to_integer(unsigned(k_in));
                Dr  <= to_integer(unsigned(k_in)) + 4;          -- D = K+4
                Fr  <= to_integer(unsigned(f_r_in));
                -- K_Pi = 32*ceil(D/32) = ((D+31)>>5)<<5
                KPi <= to_integer(
                         shift_left(shift_right(
                           to_unsigned(to_integer(unsigned(k_in)) + 4 + 31, 14),
                           5), 5));
                bsy <= '1';
                st  <= S_MAP_START;
              end if;
            end if;

          -- Pulse the 3 subblock interleavers; they stream K_Pi positions.
          when S_MAP_START =>
            map_col <= 0;
            st      <= S_MAP;

          -- Build the per-w-position map from the 3 subblock streams. Position
          -- k = map_col (the subblock counter, all three in lockstep). The
          -- d_vec target for d(row,d-index) is 3*d-index + (row-1):
          --   sys (row1): 3*s0_idx + 0,  ev (row2): 3*s1_idx + 1,
          --   od  (row3): 3*s2_idx + 2.  Filler flags pass through.
          when S_MAP =>
            if s0_v = '1' then
              mw_en    <= '1';
              mw_col   <= map_col;
              mw_sys_t <= 3 * to_integer(unsigned(s0_idx)) + 0;
              mw_sys_f <= s0_f;
              mw_ev_t  <= 3 * to_integer(unsigned(s1_idx)) + 1;
              mw_ev_f  <= s1_f;
              mw_od_t  <= 3 * to_integer(unsigned(s2_idx)) + 2;
              mw_od_f  <= s2_f;
              if s0_l = '1' then
                st <= S_DCB_START;
              else
                map_col <= map_col + 1;
              end if;
            end if;

          -- Kick the inverse circular buffer (soft scatter-accumulate). It
          -- presents f_col_o each visited position; mr_*_f (registered map
          -- read, available next cycle) returns the filler flag. The one-cycle
          -- map-read latency is naturally absorbed: de_circular_buffer's S_SKIP
          -- consumes the flag a cycle after presenting f_col in S_K0MOD/S_ADV.
          when S_DCB_START =>
            st <= S_DCB;

          when S_DCB =>
            if dcb_done = '1' then
              sc_col  <= 0;
              sc_bank <= 0;
              st      <= S_SC_PRIME;
            end if;

          -- Scatter w_soft -> d_a. Walk every w position (col 0..K_Pi-1, three
          -- banks). For NON-filler positions, write d_a_dvec(target) =
          -- sat_clip(w_soft, W_EXT). Erasure positions are non-filler too, but
          -- their w_soft is 0 -> writing 0 is harmless (the buffer is already
          -- 0-init; equals the float un-accumulated default). Filler positions
          -- carry no d-element -> skipped. The map read (mr_*) and the soft
          -- read-back (dcb_rb_*) for sc_col are both registered, valid one
          -- cycle after sc_col is presented -- S_SC_PRIME absorbs that latency.
          when S_SC_PRIME =>
            sc_col <= 1;               -- present col 1 read; col 0 lands next
            st     <= S_SC;

          when S_SC =>
            -- The map target / fill and the soft word for (sc_col-1, sc_bank)
            -- are valid now (presented the previous cycle). Select the bank.
            case sc_bank is
              when 0 =>
                t      := mr_sys_t;  isfill := mr_sys_f;
                wsoft  := to_integer(signed(dcb_rb_sys));
              when 1 =>
                t      := mr_ev_t;   isfill := mr_ev_f;
                wsoft  := to_integer(signed(dcb_rb_ev));
              when others =>
                t      := mr_od_t;   isfill := mr_od_f;
                wsoft  := to_integer(signed(dcb_rb_od));
            end case;
            if isfill = '0' then
              dw_en   <= '1';
              dw_addr <= t;
              dw_data <= sat_clip(wsoft, EXT_MIN, EXT_MAX);
            end if;
            -- advance: walk col within the bank, then next bank.
            if sc_col = KPi then       -- the previous (KPi-1) word was the last
              if sc_bank = 2 then
                fill_idx <= 0;
                fill_lo  <= '0';
                st       <= S_FILL;
              else
                sc_bank <= sc_bank + 1;
                sc_col  <= 0;          -- re-prime the next bank
                st      <= S_SC_PRIME;
              end if;
            else
              sc_col <= sc_col + 1;
            end if;

          -- Filler: d_a(1,c) and d_a(2,c) -> MAX_SENT for c=0..F_r-1. In
          -- column-major d_vec: index 3*c+0 (row1) then 3*c+1 (row2). One write
          -- per cycle (single d_a write port). Done AFTER the scatter so the
          -- +inf token overwrites any 0 / accumulated value at those positions
          -- and is exactly MAX_SENT (matches the oracle's order: saturate, then
          -- filler write).
          when S_FILL =>
            if Fr = 0 then
              out_col <= 0;
              out_sub <= 0;
              st      <= S_OUT_PRIME;
            else
              dw_en <= '1';
              if fill_lo = '0' then
                dw_addr <= 3 * fill_idx + 0;     -- row 1
                dw_data <= MAX_SENT;
                fill_lo <= '1';
              else
                dw_addr <= 3 * fill_idx + 1;     -- row 2
                dw_data <= MAX_SENT;
                fill_lo <= '0';
                if fill_idx = Fr - 1 then
                  out_col <= 0;
                  out_sub <= 0;
                  st      <= S_OUT_PRIME;
                else
                  fill_idx <= fill_idx + 1;
                end if;
              end if;
            end if;

          -- Output: stream the 3x(K+4) d_a column-major. For column out_col
          -- read d_vec[3*out_col + out_sub] (out_sub 0/1/2); collect the three
          -- into da1/2/3r, then emit a da_valid beat. dr_addr (registered)
          -- presents one word/cycle; S_OUT_PRIME primes the first read.
          when S_OUT_PRIME =>
            dr_addr <= 0;              -- present d_vec[0]
            out_sub <= 0;
            out_col <= 0;
            st      <= S_OUT;

          when S_OUT =>
            -- dr_data holds d_vec[3*out_col + out_sub] (presented last cycle).
            case out_sub is
              when 0 =>
                da1r    <= dr_data;
                dr_addr <= 3 * out_col + 1;
                out_sub <= 1;
              when 1 =>
                da2r    <= dr_data;
                dr_addr <= 3 * out_col + 2;
                out_sub <= 2;
              when others =>
                da3r <= dr_data;
                -- all three of this column captured -> emit beat next cycle.
                dav  <= '1';
                if out_col = Dr - 1 then
                  dal <= '1';
                  st  <= S_DONE;
                else
                  out_col <= out_col + 1;
                  out_sub <= 0;
                  dr_addr <= 3 * (out_col + 1) + 0;
                end if;
            end case;

          when S_DONE =>
            bsy <= '0';
            dn  <= '1';
            st  <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
