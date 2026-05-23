library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- ===========================================================================
-- turbo_decoder_term_top : termination-capable fixed-point Max-Log-MAP turbo
-- decoder (TS36.212 SS5.1.3.2), P3 of hdl/docs/decoder_roadmap.md. It is a NEW
-- entity built by copying-and-extending the P2 loop turbo_decoder_top.vhdl
-- (which is left BYTE-FOR-BYTE UNCHANGED so its cocotb lane stays green). On
-- top of the P2 half-iteration loop it adds the three P3-deferred behaviours:
--
--   1. CRC-aided EARLY TERMINATION : a new crc24_check core (CRC24A/CRC24B
--      run-time select) is run on the hard decision before the loop and after
--      each half-iteration; decoding stops on crc_ok, latching
--      iterations_performed.
--   2. FILLER bits                 : the first F_r systematic LLRs are forced
--      to the P1 +inf sentinel MAX_SENT (= EXT_MAX on the exchange grid) at
--      load, so they decode as strongly-known 0. The CRC is computed on the
--      hard decision BEFORE any filler overwrite (design.md Decision 4). On
--      OUTPUT this core streams the decoded value at filler positions, which
--      is the deterministic known 0 (the +inf token pins the bit); the oracle
--      writes NaN there. The stage-4 lane treats the oracle's NaN-at-filler as
--      the known 0 (or skips filler columns) -- the decode at those positions
--      is deterministic and identical, so the bit-exact contract holds.
--   3. HARQ soft combining         : an optional saturating accumulate of up to
--      N_RETX_MAX channel-LLR matrices into a W_HARQ buffer before decode.
--
-- ---------------------------------------------------------------------------
-- BIT-EXACT CONTRACT (the ORACLEs this entity must match exactly):
--   LOOP / EXCHANGE  : scripts/fixedpoint_turbo_decoder.m  (the P2 oracle;
--                      de-mux indexing, half-iteration framing, saturating
--                      W_EXT/W_ACC/W_IN exchange arithmetic, reverse-x_e
--                      capture, asymmetric LOWER half -- all inherited from
--                      turbo_decoder_top UNCHANGED).
--   P3 DATAPATH      : scripts/fixedpoint_turbo_decoder_term.m  (filler
--                      NaN->+inf->MAX_SENT mapping, the pre-loop column-major
--                      d_a(1:K)<0 check, the per-half (c_a+c_e)<0 check, the
--                      CRC check points and iterations_performed values,
--                      filler-before-NaN CRC order).
--   HARQ             : scripts/fixedpoint_turbo_harq_accumulate.m  (saturating
--                      buffer += d on the W_HARQ grid, re-saturate to W_EXT
--                      before the de-mux; MAX_SENT idempotent under accumulate).
--      NOTE on HARQ input grid: F_in (=4) is SHARED between the W_EXT exchange
--      word and the W_HARQ accumulator, so a W_EXT-grid input code is the SAME
--      integer code on the W_HARQ grid (W_HARQ merely has more headroom). The
--      d_a ports are W_EXT (the P2/CSV contract); each retransmission's matrix
--      is therefore expected pre-quantized to W_EXT (the existing CSV schema),
--      and this core accumulates those W_EXT codes directly into the W_HARQ
--      buffer (saturating), matching the oracle code-for-code provided the
--      vector generator quantizes each retransmission to W_EXT before emitting
--      (it already does for the single-transmission path). A per-retransmission
--      LLR magnitude > W_EXT range would be clamped upstream identically by the
--      oracle's real->W_EXT path; the accumulate headroom (W_HARQ) is what the
--      4x sum needs, exactly as the oracle.
--   CRC ALGEBRA      : crc24_check.vhdl  <-  calculate_crc_bits.m /
--                      get_crc_generator_matrix.m / get_3gpp_crc_polynomial.m.
--
--   PINNED Q-FORMAT (inherited from P1/P2 UNCHANGED; the ONLY new knob is
--   W_HARQ -- design.md "Fixed-point format" table):
--     * core/parity/termination/core-input words  : W_IN  = 9  (Q4.4, F_in=4)
--     * stored exchange words ch_sys/c_a/c_e       : W_EXT = 12 (Q7.4)
--     * combiner accumulator                       : W_ACC = 14, saturating
--     * P1 +/-inf sentinel inside the core (no new token); filler reuses the
--       +inf token = MAX_SENT at every width (EXT_MAX on the exchange grid).
--     * HARQ soft accumulator                      : W_HARQ = 16 (Q11.4),
--       saturating; re-saturated to W_EXT before the de-mux. N_RETX_MAX = 4.
--
--   REVERSE-x_e GOTCHA (CRITICAL, carried from P2): constituent_decoder streams
--   its extrinsic output in BACKWARD-SWEEP order (index N-1 first, index 0 last,
--   out_last on index 0). This controller un-reverses with a down-counter that
--   starts at N-1 on the first out_valid and decrements each beat, writing the
--   captured x_e to the body memory at that index when index < K. (Identical to
--   turbo_decoder_top.)
--
--   ASYMMETRIC LOWER half (CRITICAL, carried from P2): the UPPER half adds
--   ch_sys into both the core input (c_a+ch_sys) and the extrinsic
--   (x_e+ch_sys); the LOWER half does NEITHER add -- x'_a body = c_e[pi] and
--   c_a[pi] = x'_e directly (no +ch_sys). Preserved verbatim from P2.
--
-- ---------------------------------------------------------------------------
-- EARLY-TERMINATION DETERMINISM (design.md Decision 3): the stop point is a
-- pure function of the quantized inputs -- the CRC is checked at the SAME
-- points (pre-loop, post-upper, post-lower) in the SAME order as the oracle,
-- so iterations_performed and the decoded bits are reproducible bit-for-bit.
-- With CRC disabled (crc_en='0') S_PRECHECK / S_CRC_CHK are bypassed and the
-- behaviour is byte-for-byte the P2 loop (fixed H half-iterations).
--
-- iterations_performed is exported as a HALF-INDEX integer = round(2*iters):
--   pre-loop pass = 0, post-upper(h even) = h+1, post-lower(h odd) = h+1,
--   never pass   = 2*MAX_ITERATIONS (= H). Divide by 2 for the oracle's value.
--
-- INTERFACE: synchronous active-high rst; in_start latches K, is_tb, f_r,
-- crc_en, harq_en; d_a streamed column-major as W_EXT codes (same as P2). For
-- HARQ, present each retransmission's matrix on da_valid with harq_clear='1'
-- on the FIRST beat of the FIRST transmission (resets the buffer) and
-- harq_last='1' on the load of the FINAL retransmission (decode then proceeds
-- on the saturated combined matrix). Without HARQ (harq_en='0') a single
-- transmission loads straight through (P2 path).
-- ===========================================================================
entity turbo_decoder_term_top is
  generic (
    -- Inherited P1 core widths (defaults ARE the pin; forwarded to the core).
    W_IN    : integer := 9;    -- core input LLR (Q4.4, F_in=4)
    W_GAMMA : integer := 10;
    W_AB    : integer := 15;
    W_DELTA : integer := 17;
    W_XE    : integer := 18;   -- constituent extrinsic output width
    -- P2 exchange-format pins.
    W_EXT   : integer := 12;   -- stored c_a/c_e/ch_sys word (Q7.4)
    W_ACC   : integer := 14;   -- combiner accumulator
    -- Sizing.
    W_K     : integer := 13;   -- K width (LTE max K=6144 -> 13 bits)
    K_MAX   : integer := 6144; -- max block length
    MAX_ITERATIONS : integer := 8;     -- H = 2*MAX_ITERATIONS half-iterations
    -- P3 pins.
    N_RETX_MAX : integer := 4;         -- max HARQ retransmissions (user-pinned)
    W_HARQ     : integer := 16         -- HARQ soft-accumulator word (Q11.4)
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;                          -- sync, active-high
    in_start   : in  std_logic;                          -- latch params, begin
    k_in       : in  std_logic_vector(W_K-1 downto 0);   -- block length K
    -- P3 control, latched at in_start:
    crc_en     : in  std_logic;                          -- '1' = early term on
    is_tb      : in  std_logic;                          -- '1'=CRC24A,'0'=CRC24B
    f_r_in     : in  std_logic_vector(W_K-1 downto 0);   -- filler bit count F_r
    harq_en    : in  std_logic;                          -- '1' = HARQ accumulate
    -- LOAD: K+4 column beats of the 3x(K+4) d_a matrix (column-major), W_EXT.
    da_valid   : in  std_logic;
    da1_in     : in  std_logic_vector(W_EXT-1 downto 0); -- d_a(1,col): systematic
    da2_in     : in  std_logic_vector(W_EXT-1 downto 0); -- d_a(2,col): upper parity
    da3_in     : in  std_logic_vector(W_EXT-1 downto 0); -- d_a(3,col): lower parity
    harq_clear : in  std_logic;                          -- with first beat: reset buf
    harq_last  : in  std_logic;                          -- this load is final retx
    -- OUTPUT: K hard-decision bits, c[0] first.
    out_valid  : out std_logic;
    out_last   : out std_logic;
    c_out      : out std_logic;
    -- iterations_performed as round(2*iters) half-index (see header).
    iters_out  : out std_logic_vector(W_K-1 downto 0);
    -- status
    busy       : out std_logic;
    done       : out std_logic                           -- one-cycle pulse
  );
end entity turbo_decoder_term_top;

architecture rtl of turbo_decoder_term_top is

  constant N_MAX : integer := K_MAX + 3;   -- core block length max = K+3
  constant H     : integer := 2 * MAX_ITERATIONS;

  -- Saturation bounds.
  constant IN_MIN   : integer := -(2**(W_IN   - 1));
  constant IN_MAX   : integer :=  (2**(W_IN   - 1)) - 1;
  constant EXT_MIN  : integer := -(2**(W_EXT  - 1));
  constant EXT_MAX  : integer :=  (2**(W_EXT  - 1)) - 1;   -- = MAX_SENT @ W_EXT
  constant ACC_MIN  : integer := -(2**(W_ACC  - 1));
  constant ACC_MAX  : integer :=  (2**(W_ACC  - 1)) - 1;
  constant HARQ_MIN : integer := -(2**(W_HARQ - 1));
  constant HARQ_MAX : integer :=  (2**(W_HARQ - 1)) - 1;

  -- ---- Reused cores (UNMODIFIED), declared as components. ----
  component constituent_decoder is
    generic (
      W_IN    : integer := 9; W_GAMMA : integer := 10; W_AB : integer := 15;
      W_DELTA : integer := 17; W_XE : integer := 18; W_K : integer := 13;
      N_MAX   : integer := 6147
    );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_in : in std_logic_vector(W_K-1 downto 0); in_valid : in std_logic;
      x_a_in : in std_logic_vector(W_IN-1 downto 0);
      z_a_in : in std_logic_vector(W_IN-1 downto 0);
      out_valid : out std_logic; out_last : out std_logic;
      x_e_out : out std_logic_vector(W_XE-1 downto 0);
      busy : out std_logic; done : out std_logic
    );
  end component;

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

  component crc24_check is
    generic ( K_MAX : integer := 6144; W_K : integer := 13; L : integer := 24 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_in : in std_logic_vector(W_K-1 downto 0);
      is_tb : in std_logic; in_valid : in std_logic; bit_in : in std_logic;
      crc_done : out std_logic; crc_ok : out std_logic
    );
  end component;

  -- ---- LLR / extrinsic memories (integer codes). ----
  type in_mem_t  is array (0 to N_MAX-1) of integer;  -- W_IN-grid words
  signal za_mem  : in_mem_t;
  signal zpa_mem : in_mem_t;
  type ext_mem_t is array (0 to K_MAX-1) of integer;  -- W_EXT-grid words
  signal chs_mem : ext_mem_t;  -- ch_sys[0..K-1]
  type term_t is array (0 to 2) of integer;
  signal xa_term  : term_t;
  signal xpa_term : term_t;
  signal ca_mem : ext_mem_t;
  signal ce_mem : ext_mem_t;

  -- Pre-loop hard decision c0 = (d_a_q(1:K) < 0) in COLUMN-MAJOR linear order
  -- (the float-quirk oracle output on a pre-loop CRC pass). Captured in
  -- S_PRECHK_FEED alongside the CRC feed; streamed by S_OUT when the pre-loop
  -- check passes (preloop_pass='1'), because on a pre-loop pass the oracle
  -- returns c = c0, NOT (c_a+c_e)<0 (which would read the un-run loop state).
  type bit_mem_t is array (0 to K_MAX-1) of std_logic;
  signal c0_mem        : bit_mem_t;
  signal preloop_pass  : std_logic := '0';

  -- HARQ soft buffer: 3 rows x (K+4) cols on the W_HARQ grid.
  type harq_row_t is array (0 to K_MAX+3) of integer;
  type harq_buf_t is array (0 to 2) of harq_row_t;
  signal harq_buf : harq_buf_t;

  signal Kr : integer range 0 to K_MAX := 0;
  signal Nr : integer range 0 to N_MAX := 0;   -- N = K+3
  signal Fr : integer range 0 to K_MAX := 0;   -- filler bit count

  -- Latched P3 control.
  signal crc_on   : std_logic := '0';
  signal tb_lat   : std_logic := '0';
  signal harq_on  : std_logic := '0';

  -- ---- FSM. ----
  type state_t is (
    S_IDLE, S_LOAD_D,
    S_ROM_START, S_ROM_WAIT,
    S_PRECHK_FEED, S_PRECHK_WAIT,                  -- pre-loop CRC check
    S_HALF_DISPATCH,
    S_UP_DEC,
    S_LO_PI1_START, S_LO_PI1, S_LO_DEC, S_LO_PI2_START, S_LO_PI2,
    S_CRC_FEED, S_CRC_WAIT,                        -- per-half CRC check
    S_FINAL, S_OUT, S_DONE);
  signal st : state_t := S_IDLE;

  signal h_cnt : integer range 0 to H + 1 := 0;
  signal lcol  : integer range 0 to K_MAX + 4 := 0;

  -- Core feed / capture.
  signal cd_start    : std_logic := '0';
  signal cd_in_valid : std_logic := '0';
  signal cd_xa       : std_logic_vector(W_IN-1 downto 0) := (others => '0');
  signal cd_za       : std_logic_vector(W_IN-1 downto 0) := (others => '0');
  signal cd_out_valid: std_logic;
  signal cd_out_last : std_logic;
  signal cd_xe       : std_logic_vector(W_XE-1 downto 0);
  signal cd_busy     : std_logic;
  signal cd_done     : std_logic;
  signal cd_k        : std_logic_vector(W_K-1 downto 0) := (others => '0');

  signal feed_idx : integer range 0 to N_MAX := 0;
  signal cap_idx  : integer range 0 to N_MAX := 0;
  signal cap_seen : std_logic := '0';

  -- QPP address generation.
  signal rom_start, rom_done, rom_sup : std_logic := '0';
  signal rom_d0, rom_step : std_logic_vector(QPP_W-1 downto 0);
  signal d0c, stepc       : std_logic_vector(QPP_W-1 downto 0) := (others => '0');
  signal qi_start, qi_valid, qi_last : std_logic := '0';
  signal qi_pi  : std_logic_vector(QPP_W-1 downto 0);

  signal xpa_body : ext_mem_t;
  signal xpe_body : ext_mem_t;
  signal pi_k     : integer range 0 to K_MAX := 0;

  -- CRC core wiring.
  signal crc_start    : std_logic := '0';
  signal crc_in_valid : std_logic := '0';
  signal crc_bit      : std_logic := '0';
  signal crc_done_s   : std_logic;
  signal crc_ok_s     : std_logic;
  signal crc_feed_idx : integer range 0 to K_MAX := 0;
  signal crc_armed    : std_logic := '0';   -- '1' after start consumed, feeding

  -- iterations_performed (half-index = round(2*iters)).
  signal iters_half : integer range 0 to H := H;

  -- Output streaming.
  signal out_idx : integer range 0 to K_MAX := 0;
  signal ov, ol, dn, bsy : std_logic := '0';
  signal cbit : std_logic := '0';

  -- Saturating helpers (clamp, no wrap).
  function sat_clip(x, lo, hi : integer) return integer is
  begin
    if x > hi then return hi; elsif x < lo then return lo; else return x; end if;
  end function;

  function sat_add(a, b, lo, hi : integer) return integer is
    variable s : integer;
  begin
    s := a + b;
    if s > hi then return hi; elsif s < lo then return lo; else return s; end if;
  end function;

begin
  -- ---- Core instantiations (UNMODIFIED). ----
  u_cd : constituent_decoder
    generic map (W_IN => W_IN, W_GAMMA => W_GAMMA, W_AB => W_AB,
                 W_DELTA => W_DELTA, W_XE => W_XE, W_K => W_K, N_MAX => N_MAX)
    port map (clk => clk, rst => rst, start => cd_start, k_in => cd_k,
              in_valid => cd_in_valid, x_a_in => cd_xa, z_a_in => cd_za,
              out_valid => cd_out_valid, out_last => cd_out_last,
              x_e_out => cd_xe, busy => cd_busy, done => cd_done);

  u_rom : qpp_rom
    port map (clk => clk, rst => rst, start => rom_start,
              k_in => std_logic_vector(to_unsigned(Kr, QPP_W)),
              done => rom_done, supported => rom_sup,
              d0_o => rom_d0, step_o => rom_step);

  u_qi : qpp_interleaver
    generic map (W => QPP_W)
    port map (clk => clk, rst => rst, start => qi_start,
              k_in => std_logic_vector(to_unsigned(Kr, QPP_W)),
              d0 => d0c, step => stepc,
              valid => qi_valid, last => qi_last, pi_o => qi_pi);

  u_crc : crc24_check
    generic map (K_MAX => K_MAX, W_K => W_K, L => 24)
    port map (clk => clk, rst => rst, start => crc_start,
              k_in => std_logic_vector(to_unsigned(Kr, W_K)),
              is_tb => tb_lat, in_valid => crc_in_valid, bit_in => crc_bit,
              crc_done => crc_done_s, crc_ok => crc_ok_s);

  cd_k <= std_logic_vector(to_unsigned(Kr, W_K));

  out_valid <= ov;
  out_last  <= ol;
  c_out     <= cbit;
  busy      <= bsy;
  done      <= dn;
  iters_out <= std_logic_vector(to_unsigned(iters_half, W_K));

  process (clk)
    variable pi_idx  : integer;
    variable acc     : integer;
    variable xe_code : integer;
    variable za_v, xa_v : integer;
    variable d1v, d2v, d3v : integer;   -- HARQ-combined column values (W_EXT)
    variable cm_idx  : integer;         -- column-major linear index helper
    variable cm_row  : integer;
    variable cm_col  : integer;
    variable sgn_neg : std_logic;
  begin
    if rising_edge(clk) then
      cd_start     <= '0';
      cd_in_valid  <= '0';
      rom_start    <= '0';
      qi_start     <= '0';
      crc_start    <= '0';
      crc_in_valid <= '0';
      ov           <= '0';
      ol           <= '0';
      dn           <= '0';

      if rst = '1' then
        st  <= S_IDLE;
        bsy <= '0';
      else
        case st is

          -- =============================================================
          when S_IDLE =>
            if in_start = '1' then
              Kr      <= to_integer(unsigned(k_in));
              Nr      <= to_integer(unsigned(k_in)) + 3;
              Fr      <= to_integer(unsigned(f_r_in));
              crc_on  <= crc_en;
              tb_lat  <= is_tb;
              harq_on <= harq_en;
              lcol    <= 0;
              preloop_pass <= '0';
              bsy     <= '1';
              st      <= S_LOAD_D;
            end if;

          -- ---- LOAD: de-mux the 3x(K+4) d_a column stream. -------------
          -- P3 additions vs P2:
          --   (a) HARQ: when harq_on='1', accumulate the incoming W_EXT
          --       codes into the W_HARQ buffer (saturating), and de-mux the
          --       SATURATED-to-W_EXT combined column. harq_clear (first beat)
          --       resets the buffer. The decode proceeds after the load that
          --       carries harq_last='1'. When harq_on='0' the column values
          --       pass straight through (P2 behaviour).
          --   (b) FILLER: the first Fr systematic body positions (k<Fr) force
          --       ch_sys = EXT_MAX (the +inf token / MAX_SENT). Parity rows
          --       are untouched (the oracle only sets d_a(1,filler)=inf).
          when S_LOAD_D =>
            if da_valid = '1' then
              -- HARQ accumulate (saturating) on the W_HARQ grid, else passthrough.
              if harq_on = '1' then
                if harq_clear = '1' and lcol = 0 then
                  -- reset whole buffer to 0 (float resetImpl) before accumulate
                  for r in 0 to 2 loop
                    for cc in 0 to K_MAX+3 loop
                      harq_buf(r)(cc) <= 0;
                    end loop;
                  end loop;
                end if;
                -- accumulate this column's 3 codes
                if harq_clear = '1' and lcol = 0 then
                  d1v := sat_clip(to_integer(signed(da1_in)), HARQ_MIN, HARQ_MAX);
                  d2v := sat_clip(to_integer(signed(da2_in)), HARQ_MIN, HARQ_MAX);
                  d3v := sat_clip(to_integer(signed(da3_in)), HARQ_MIN, HARQ_MAX);
                else
                  d1v := sat_add(harq_buf(0)(lcol),
                                 to_integer(signed(da1_in)), HARQ_MIN, HARQ_MAX);
                  d2v := sat_add(harq_buf(1)(lcol),
                                 to_integer(signed(da2_in)), HARQ_MIN, HARQ_MAX);
                  d3v := sat_add(harq_buf(2)(lcol),
                                 to_integer(signed(da3_in)), HARQ_MIN, HARQ_MAX);
                end if;
                harq_buf(0)(lcol) <= d1v;
                harq_buf(1)(lcol) <= d2v;
                harq_buf(2)(lcol) <= d3v;
                -- de-mux uses the W_EXT-saturated combined codes
                d1v := sat_clip(d1v, EXT_MIN, EXT_MAX);
                d2v := sat_clip(d2v, EXT_MIN, EXT_MAX);
                d3v := sat_clip(d3v, EXT_MIN, EXT_MAX);
              else
                d1v := to_integer(signed(da1_in));
                d2v := to_integer(signed(da2_in));
                d3v := to_integer(signed(da3_in));
              end if;

              -- De-mux (identical column mapping to P2/turbo_decoder.m).
              if lcol < Kr then
                -- body column. FILLER: first Fr systematic positions -> EXT_MAX.
                if lcol < Fr then
                  chs_mem(lcol) <= EXT_MAX;                       -- +inf token
                else
                  chs_mem(lcol) <= sat_clip(d1v, EXT_MIN, EXT_MAX);
                end if;
                za_mem(lcol)  <= sat_clip(d2v, IN_MIN, IN_MAX);
                zpa_mem(lcol) <= sat_clip(d3v, IN_MIN, IN_MAX);
              elsif lcol = Kr then
                xa_term(0)    <= sat_clip(d1v, IN_MIN, IN_MAX);   -- x_a(K+1)
                za_mem(Kr)    <= sat_clip(d2v, IN_MIN, IN_MAX);   -- z_a(K+1)
                xa_term(1)    <= sat_clip(d3v, IN_MIN, IN_MAX);   -- x_a(K+2)
              elsif lcol = Kr + 1 then
                za_mem(Kr+1)  <= sat_clip(d1v, IN_MIN, IN_MAX);   -- z_a(K+2)
                xa_term(2)    <= sat_clip(d2v, IN_MIN, IN_MAX);   -- x_a(K+3)
                za_mem(Kr+2)  <= sat_clip(d3v, IN_MIN, IN_MAX);   -- z_a(K+3)
              elsif lcol = Kr + 2 then
                xpa_term(0)   <= sat_clip(d1v, IN_MIN, IN_MAX);   -- x'_a(K+1)
                zpa_mem(Kr)   <= sat_clip(d2v, IN_MIN, IN_MAX);   -- z'_a(K+1)
                xpa_term(1)   <= sat_clip(d3v, IN_MIN, IN_MAX);   -- x'_a(K+2)
              else
                zpa_mem(Kr+1) <= sat_clip(d1v, IN_MIN, IN_MAX);   -- z'_a(K+2)
                xpa_term(2)   <= sat_clip(d2v, IN_MIN, IN_MAX);   -- x'_a(K+3)
                zpa_mem(Kr+2) <= sat_clip(d3v, IN_MIN, IN_MAX);   -- z'_a(K+3)
              end if;

              if lcol = Kr + 3 then
                if harq_on = '1' and harq_last = '0' then
                  -- more retransmissions to come: accept the next load matrix.
                  -- (Buffer retained; restart the column counter, stay in LOAD,
                  --  do NOT decode yet.)
                  lcol <= 0;
                  st   <= S_LOAD_D;
                else
                  for k in 0 to K_MAX-1 loop
                    ca_mem(k) <= 0;          -- c_a = 0 init
                  end loop;
                  h_cnt      <= 0;
                  iters_half <= H;           -- default "never passed"
                  st         <= S_ROM_START;
                end if;
              else
                lcol <= lcol + 1;
              end if;
            end if;

          -- ---- ROM lookup (K -> d0,step), done ONCE; result cached. ----
          when S_ROM_START =>
            rom_start <= '1';
            st        <= S_ROM_WAIT;

          when S_ROM_WAIT =>
            if rom_done = '1' then
              d0c   <= rom_d0;
              stepc <= rom_step;
              if crc_on = '1' then
                crc_start    <= '1';     -- arm CRC core for the pre-loop check
                crc_feed_idx <= 0;
                crc_armed    <= '0';     -- start consumed next cycle, then feed
                st           <= S_PRECHK_FEED;
              else
                st <= S_HALF_DISPATCH;
              end if;
            end if;

          -- ---- PRE-LOOP CRC check (turbo_decoder_term.m: c0 = d_a_q(1:K)<0
          --      using COLUMN-MAJOR linear indexing over the 3x(K+4) matrix).
          --      element i (0-based) -> row (i mod 3), col floor(i/3). The
          --      systematic body (row0) carries the filler EXT_MAX, the parity
          --      rows the W_IN-clipped codes, termination columns the triplets.
          --      We reconstruct each element's stored W_EXT/W_IN code to test
          --      its sign, exactly as the oracle tests d_a_q(1:K) < 0. ----
          when S_PRECHK_FEED =>
            -- The crc_start pulse is consumed by the core on the first cycle in
            -- this state; only begin feeding once armed (the cycle after).
            if crc_armed = '0' then
              crc_armed <= '1';
            elsif crc_feed_idx < Kr then
              cm_idx := crc_feed_idx;
              cm_row := cm_idx mod 3;
              cm_col := cm_idx / 3;
              -- Reconstruct the quantized matrix element (row cm_row, col cm_col)
              -- on the W_EXT grid sign, matching the oracle's d_a_q. Body cols
              -- (cm_col < Kr): row0=ch_sys (incl. filler EXT_MAX>0), row1=z_a,
              -- row2=z'_a. Termination cols (cm_col >= Kr) reuse the de-muxed
              -- triplets; only relevant when K is small enough that cm_col
              -- reaches the termination region (cm_col up to (K-1)/3 < K, so
              -- for K>=2 cm_col stays in the body, but handle generally).
              if cm_col < Kr then
                if cm_row = 0 then
                  acc := chs_mem(cm_col);
                elsif cm_row = 1 then
                  acc := za_mem(cm_col);
                else
                  acc := zpa_mem(cm_col);
                end if;
              else
                -- termination region (cm_col = Kr..Kr+3): map back via de-mux.
                acc := 0;   -- unreachable for K>=2 (cm_col<=(K-1)/3); safe default
              end if;
              if acc < 0 then sgn_neg := '1'; else sgn_neg := '0'; end if;
              crc_bit      <= sgn_neg;
              crc_in_valid <= '1';
              -- Capture the pre-loop hard decision bit (= the oracle's c0) so
              -- S_OUT can stream it verbatim if the pre-loop CRC passes.
              c0_mem(crc_feed_idx) <= sgn_neg;
              crc_feed_idx <= crc_feed_idx + 1;
            end if;
            if crc_done_s = '1' then
              st <= S_PRECHK_WAIT;
            end if;

          when S_PRECHK_WAIT =>
            if crc_ok_s = '1' then
              iters_half   <= 0;          -- pre-loop pass
              preloop_pass <= '1';        -- S_OUT streams c0, not (c_a+c_e)<0
              out_idx      <= 0;
              st           <= S_FINAL;
            else
              st <= S_HALF_DISPATCH;
            end if;

          -- ---- HALF-ITERATION DISPATCH. (P2, unchanged.) ----------------
          when S_HALF_DISPATCH =>
            if h_cnt = H then
              iters_half <= H;            -- CRC never passed / disabled
              out_idx    <= 0;
              st         <= S_FINAL;
            else
              cd_start <= '1';
              feed_idx <= 0;
              cap_idx  <= 0;
              cap_seen <= '0';
              if (h_cnt mod 2) = 0 then
                st <= S_UP_DEC;
              else
                st <= S_LO_PI1_START;
              end if;
            end if;

          -- =================== UPPER half (P2, unchanged) =============
          when S_UP_DEC =>
            if feed_idx < Nr then
              if feed_idx < Kr then
                acc  := sat_add(ca_mem(feed_idx), chs_mem(feed_idx),
                                ACC_MIN, ACC_MAX);
                xa_v := sat_clip(acc, IN_MIN, IN_MAX);
              else
                xa_v := xa_term(feed_idx - Kr);
              end if;
              za_v := za_mem(feed_idx);
              cd_xa       <= std_logic_vector(to_signed(xa_v, W_IN));
              cd_za       <= std_logic_vector(to_signed(za_v, W_IN));
              cd_in_valid <= '1';
              feed_idx    <= feed_idx + 1;
            end if;
            if cd_out_valid = '1' then
              if cap_seen = '0' then
                cap_idx  <= Nr - 1;
                cap_seen <= '1';
                if (Nr - 1) < Kr then
                  acc := sat_add(to_integer(signed(cd_xe)),
                                 chs_mem(Nr-1), ACC_MIN, ACC_MAX);
                  ce_mem(Nr-1) <= sat_clip(acc, EXT_MIN, EXT_MAX);
                end if;
              else
                if (cap_idx - 1) < Kr then
                  acc := sat_add(to_integer(signed(cd_xe)),
                                 chs_mem(cap_idx-1), ACC_MIN, ACC_MAX);
                  ce_mem(cap_idx-1) <= sat_clip(acc, EXT_MIN, EXT_MAX);
                end if;
                cap_idx <= cap_idx - 1;
              end if;
            end if;
            if cd_done = '1' then
              -- P3: CRC check after this UPPER half before advancing h_cnt.
              if crc_on = '1' then
                crc_start    <= '1';
                crc_feed_idx <= 0;
                crc_armed    <= '0';
                st           <= S_CRC_FEED;
              else
                h_cnt <= h_cnt + 1;
                st    <= S_HALF_DISPATCH;
              end if;
            end if;

          -- =================== LOWER half (P2, unchanged) =============
          when S_LO_PI1_START =>
            qi_start <= '1';
            pi_k     <= 0;
            st       <= S_LO_PI1;

          when S_LO_PI1 =>
            if qi_valid = '1' then
              pi_idx := to_integer(unsigned(qi_pi));
              xpa_body(pi_k) <= sat_clip(ce_mem(pi_idx), IN_MIN, IN_MAX);
              if qi_last = '1' then
                cd_start <= '1';
                feed_idx <= 0;
                cap_idx  <= 0;
                cap_seen <= '0';
                st       <= S_LO_DEC;
              else
                pi_k <= pi_k + 1;
              end if;
            end if;

          when S_LO_DEC =>
            if feed_idx < Nr then
              if feed_idx < Kr then
                xa_v := sat_clip(xpa_body(feed_idx), IN_MIN, IN_MAX);
              else
                xa_v := xpa_term(feed_idx - Kr);
              end if;
              za_v := zpa_mem(feed_idx);
              cd_xa       <= std_logic_vector(to_signed(xa_v, W_IN));
              cd_za       <= std_logic_vector(to_signed(za_v, W_IN));
              cd_in_valid <= '1';
              feed_idx    <= feed_idx + 1;
            end if;
            if cd_out_valid = '1' then
              xe_code := to_integer(signed(cd_xe));
              if cap_seen = '0' then
                cap_idx  <= Nr - 1;
                cap_seen <= '1';
                if (Nr - 1) < Kr then
                  xpe_body(Nr-1) <= sat_clip(xe_code, EXT_MIN, EXT_MAX);
                end if;
              else
                if (cap_idx - 1) < Kr then
                  xpe_body(cap_idx-1) <= sat_clip(xe_code, EXT_MIN, EXT_MAX);
                end if;
                cap_idx <= cap_idx - 1;
              end if;
            end if;
            if cd_done = '1' then
              st <= S_LO_PI2_START;
            end if;

          when S_LO_PI2_START =>
            qi_start <= '1';
            pi_k     <= 0;
            st       <= S_LO_PI2;

          when S_LO_PI2 =>
            if qi_valid = '1' then
              pi_idx := to_integer(unsigned(qi_pi));
              ca_mem(pi_idx) <= xpe_body(pi_k);
              if qi_last = '1' then
                -- P3: CRC check after this LOWER half before advancing h_cnt.
                if crc_on = '1' then
                  crc_start    <= '1';
                  crc_feed_idx <= 0;
                  crc_armed    <= '0';
                  st           <= S_CRC_FEED;
                else
                  h_cnt <= h_cnt + 1;
                  st    <= S_HALF_DISPATCH;
                end if;
              else
                pi_k <= pi_k + 1;
              end if;
            end if;

          -- ---- PER-HALF CRC check (oracle: c = (c_a+c_e)<0 over K bits,
          --      streamed to crc24_check). On crc_ok latch iters_half and go
          --      to S_FINAL; else advance h_cnt and continue the loop. ----
          when S_CRC_FEED =>
            if crc_armed = '0' then
              crc_armed <= '1';        -- start consumed; feed from next cycle
            elsif crc_feed_idx < Kr then
              acc := sat_add(ca_mem(crc_feed_idx), ce_mem(crc_feed_idx),
                             ACC_MIN, ACC_MAX);
              if acc < 0 then crc_bit <= '1'; else crc_bit <= '0'; end if;
              crc_in_valid <= '1';
              crc_feed_idx <= crc_feed_idx + 1;
            end if;
            if crc_done_s = '1' then
              st <= S_CRC_WAIT;
            end if;

          when S_CRC_WAIT =>
            if crc_ok_s = '1' then
              -- iters_half = round(2*iters): post-upper(h even)=h+1,
              -- post-lower(h odd)=h+1 -> in both cases h_cnt+1 (since the half
              -- just completed has not yet incremented h_cnt). Oracle:
              --   post-upper: (h/2)+0.5  -> 2x = h+1
              --   post-lower: (h+1)/2    -> 2x = h+1
              iters_half <= h_cnt + 1;
              out_idx    <= 0;
              st         <= S_FINAL;
            else
              h_cnt <= h_cnt + 1;
              st    <= S_HALF_DISPATCH;
            end if;

          -- =================== FINISH (P2, + iters export) ===========
          when S_FINAL =>
            out_idx <= 0;
            st      <= S_OUT;

          when S_OUT =>
            if preloop_pass = '1' then
              -- Pre-loop CRC pass: the oracle returns c = c0 (the column-major
              -- pre-loop hard decision), NOT (c_a+c_e)<0.
              cbit <= c0_mem(out_idx);
            else
              acc := sat_add(ca_mem(out_idx), ce_mem(out_idx), ACC_MIN, ACC_MAX);
              if acc < 0 then cbit <= '1'; else cbit <= '0'; end if;
            end if;
            ov <= '1';
            if out_idx = Kr - 1 then
              ol <= '1';
              st <= S_DONE;
            else
              out_idx <= out_idx + 1;
            end if;

          when S_DONE =>
            bsy <= '0';
            dn  <= '1';
            st  <= S_IDLE;

        end case;
      end if;
    end if;
  end process;
end architecture rtl;
