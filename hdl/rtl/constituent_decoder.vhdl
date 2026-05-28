library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Fixed-point Max-Log-MAP Log-BCJR constituent decoder, TS36.212
-- SS5.1.3.2. Bit-exact port of scripts/fixedpoint_constituent_decoder.m
-- (the authored fixed-point oracle), which is itself the Max-Log-MAP
-- fixed-point port of constituent_decoder.m (the long-trusted float model).
-- See openspec/changes/add-fpga-constituent-decoder/design.md.
--
-- ===================================================================
-- BIT-EXACTNESS CONTRACT (must match fixedpoint_constituent_decoder.m
-- exactly; the cocotb lane, task 4.x, checks bit-for-bit):
-- ===================================================================
--  * Pinned Q-format (design.md "Fixed-point format - pinned"):
--      input LLR x_a,z_a : W_IN    = 9  (signed, Q4.4, F_in=4)
--      branch metric g   : W_GAMMA = 10 (g in {0,-x,-z,-x-z})
--      alpha/beta        : W_AB    = 15 (post per-step max-norm)
--      delta=a+b+g_z     : W_DELTA = 17
--      extrinsic x_e     : W_XE    = 18
--  * Max-Log-MAP: maxstar -> plain max. max is exact + associative in
--    fixed-point so reduction order is irrelevant for the value; the
--    *only* contract is identical quantization, saturation and
--    normalization point.
--  * Trellis (identical row order / index 1..8 to the .m):
--        From To  x z          From To  x z
--     1:  1  1  0 0    9:  1  5  1 1
--     2:  2  5  0 0   10:  2  1  1 1
--     3:  3  6  0 1   11:  3  2  1 0
--     4:  4  2  0 1   12:  4  6  1 0
--     5:  5  3  0 1   13:  5  7  1 0
--     6:  6  7  0 1   14:  6  3  1 0
--     7:  7  8  0 0   15:  7  4  1 1
--     8:  8  4  0 0   16:  8  8  1 1
--    => gamma(t)   = -x*xbit(t) - z*zbit(t)
--       gamma_z(t) = -z*zbit(t)   (zbit set for t in {3,4,5,6,9,10,15,16})
--  * alpha aggregation per next-state s (into_state, ascending t-index):
--       s1:{1,10} s2:{4,11} s3:{5,14} s4:{8,15}
--       s5:{2, 9} s6:{3,12} s7:{6,13} s8:{7,16}
--    beta aggregation per state s (outof_state, ascending t-index):
--       s1:{1, 9} s2:{2,10} s3:{3,11} s4:{4,12}
--       s5:{5,13} s6:{6,14} s7:{7,15} s8:{8,16}
--  * Per-step max-normalization: after each alpha (and each beta)
--    trellis step compute m = max over the 8 states, store metric - m
--    (saturating). Same max-set, same subtraction point as the .m.
--  * +/-inf sentinel: impossible alpha/beta init states = MIN_SENT =
--    -2^(W_AB-1) = -16384. Saturating add can only push it further from
--    0, so max(MIN_SENT, real) == real always (design.md §4a).
--  * Saturating adds/subs: every alpha/beta/delta/x_e add or sub clamps
--    to its width's [min,max], never wraps.
--  * Extrinsic: x_e = sat_sub( max(delta | x=0), max(delta | x=1) ) in
--    W_XE signed.
--
-- INPUT QUANTIZATION NOTE: like the upstream chain, this core receives
-- already-quantized W_IN signed integer LLR codes on x_a_in/z_a_in. The
-- round-half-away-from-zero quantization in the .m is applied by the
-- vector generator (task 2.x); the HDL operates on the integer codes.
--
-- ARCHITECTURE: full-block alpha storage (8 x (K+3)), sim-first per
-- design.md §5. Latency ~3*(K+3) cycles: load K+3, forward K+3,
-- backward+extrinsic K+3.
--
-- ===================================================================
-- M4K BLOCK-RAM INFERENCE REWORK (add-fpga-decoder-block-ram-inference,
-- stage 1) -- the decoder-side analog of the archived TX block-RAM fix:
-- ===================================================================
-- Quartus II 13.0sp1 refuses to map an array to Cyclone II M4K when its
-- write lives inside the synchronous-reset-guarded FSM body
-- (if rst='1' then .. else case st ..) and/or when the read is
-- asynchronous; it falls back to LE registers (Total memory bits : 0).
-- The original constituent decoder had exactly this on all three of its
-- memories. The fix (bit-exact -- the constituent_decoder cocotb lane is
-- the gate, vectors unchanged):
--   * alpha_mem is repacked as a (K+3)-deep array of ONE wide word per
--     column (STATES*W_AB = 120 bits), so the per-step max-norm reads/writes
--     the whole 8-state column in one M4K access. Its write and registered
--     read live in a dedicated unconditional clocked memory process
--     (a_mem); the FSM drives only a_we / a_waddr / a_wdata (the packed
--     column) and a_raddr, never the array under the reset/case. The
--     forward recurrence FORWARDS the just-computed column in a register
--     (alpha_prev) instead of a RAM read -- the value is in hand the cycle
--     it is written -- so the forward sweep has NO read bubble and emits
--     the identical alpha sequence. The backward delta sweep re-reads
--     columns via a_raddr (registered); a one-cycle prime beat
--     (S_BWD_PRIME) absorbs the read latency so x_e is bit-identical.
--   * xa_mem / za_mem become clean 1W/1R simple-dual-port arrays: write
--     lifted into the same memory process (in_we / in_waddr / in_wdata),
--     read registered (in_raddr -> xa_rd/za_rd) and aligned to the same
--     backward prime beat. The forward sweep does not need them from RAM
--     (gamma uses the column-(kidx-1) inputs, forwarded in xq_p/zq_p
--     registers from the prior cycle, set up by a forward prime beat
--     S_FWD_PRIME so column-0 inputs are in hand for the first step).
--   * ramstyle = "M4K" pins the intent on each array; the structural fix
--     (write lifted out of the reset/case, sync read) is what makes it
--     infer. Power-up init := (others=>'0') kept; no async clear on the
--     array body (the alpha col-0 init is now a top-level memory write).
-- Recorded Quartus II 13.0sp1 (EP2C35F672C6) standalone fit, N_MAX=515
-- (K=512 sizing so the full-block alpha store fits on-chip):
--   * BEFORE (master, async read + write in the reset/case body):
--       Total memory bits = 0; M4K = 0 -- all three arrays mapped to LE
--       register fabric (the inference blocker).
--   * AFTER (this rework): Total memory bits = 71,070; M4K = 35/105 --
--       alpha_mem 515x120 = 61,800 bits / 30 M4K (Simple Dual Port,
--       READ_DURING_WRITE = OLD_DATA), xa_mem / za_mem each 515x9 = 4,635
--       bits / 3 M4K. Logic = 9,371 LE / 33,216 (28%); registers = 808;
--       embedded multipliers = 0/70 (datapath is max/add only). Fits the
--       EP2C35 with large headroom. 0 A&S / Fitter errors.
--   * Fmax (sign-off slow model) = 15.58 MHz: the single-cycle FORWARD
--       alpha recurrence (8-way saturating add -> 8-way max-norm ->
--       saturate, ~64 ns combinational cone) is the bottleneck. This cone
--       is PRE-EXISTING in the algorithm (master's async-read version fed
--       the identical arithmetic) -- the M4K rework did NOT regress it.
--       Closing 50 MHz needs the algorithmic forward-recurrence pipelining
--       (a separate increment, see the change's design Risks); stage 1's
--       gate is M4K INFERENCE (memory bits>0 / M4K>0 / mults=0 / fits),
--       which is met. Bit-exactness is preserved (constituent_decoder
--       cocotb lane: 27/27 frames bit-exact; turbo_decoder_top and
--       turbo_decoder_term_top lanes green; golden vectors byte-identical).
--
-- INTERFACE (K-agnostic streaming, repo convention: synchronous
-- active-high rst, start latches K, out_valid/out_last; busy/done
-- status). See qpp_interleaver.vhdl / turbo_encoder.vhdl for the style.

entity constituent_decoder is
  generic (
    -- Pinned widths (design.md). Exposed as generics so the same
    -- parameter set is shared with the reference; defaults ARE the pin.
    W_IN    : integer := 9;
    W_GAMMA : integer := 10;
    W_AB    : integer := 15;
    W_DELTA : integer := 17;
    W_XE    : integer := 18;
    W_K     : integer := 13;     -- K width (LTE max K=6144 -> 13 bits)
    N_MAX   : integer := 6147;   -- max N = K+3 = 6144+3
    -- ===================================================================
    -- EXACT_LOGMAP (add-fpga-decoder-exact-log-map, stage 3, task 2.1)
    -- ===================================================================
    -- Default FALSE => the proven Max-Log-MAP core, BIT-EXACT to the
    -- existing golden vectors (max*(a,b) collapses to plain max(a,b), the
    -- correction add is 0). Synthesis constant-folds the LUT/adder away, so
    -- the default build is structurally identical to today's core and every
    -- reused top (turbo_decoder_top / turbo_decoder_term_top / rx_chain_top)
    -- stays green unchanged.
    --   TRUE => exact Log-MAP, bit-exact to
    -- scripts/fixedpoint_constituent_decoder_logmap.m: after every 2-way
    -- max(a,b) of the alpha/beta recurrences and every 2-way node of the two
    -- extrinsic delta max-trees, add the Jacobian correction
    -- corr_code(sat(|a-b|,0..LUT_D-1)) from a tiny quantized ROM
    -- (f(d)=ln(1+e^-d) at the F_in=4 grid), saturating. The correction is
    -- NOT applied at the per-step max-normalization nor the final
    -- sat_sub(log_p0,log_p1) (design.md §2). The extrinsic 8-way fold is a
    -- sequential LEFT FOLD in ascending transition index (max* is NOT
    -- associative, so the fold order is part of the contract; design.md §4).
    EXACT_LOGMAP : boolean := false;
    -- ===================================================================
    -- ANCHOR_NORM (add-fpga-decoder-recurrence-pipelining, stage 1 task 1.2)
    -- ===================================================================
    -- Default FALSE => keep the per-step 8-way max-normalization in BOTH the
    -- forward alpha step (S_FWD) and the backward beta step (S_BWD): compute
    -- m = max over the 8 states, store metric - m (saturating). Bit-exact to
    -- the existing golden vectors.
    --   TRUE => ANCHOR normalization: subtract STATE 1 (m := new_a(1) /
    -- new_b(1)) instead of the 8-way running max. This removes the whole 8-way
    -- max TREE from the recurrence cone (the path-(1) lever, design.md 2b). It
    -- is OUTPUT-equivalent in Max-Log-MAP mode: the per-step offset is COMMON
    -- to all 8 states, and the extrinsic x_e = max(delta|x=0) - max(delta|x=1)
    -- is a difference, so the common offset cancels exactly (the same
    -- normalization-invariance the per-step max-norm relies on). The INTERNAL
    -- alpha/beta values change (state 1 is now the 0-anchor instead of the
    -- per-step max), but x_e / the decoded bits are identical; no decoder lane
    -- asserts on internal alpha/beta. Pairs with EXACT_LOGMAP independently
    -- (anchor vs max-norm is a normalization-point choice; the max* correction
    -- is unchanged).
    ANCHOR_NORM : boolean := false;
    -- ===================================================================
    -- BAL_TREE_FOLD (add-fpga-decoder-recurrence-pipelining, stage 1 task 1.1)
    -- ===================================================================
    -- Default FALSE => keep the SEQUENTIAL LEFT FOLD computing max0/max1 over
    -- the 8 x=0 / 8 x=1 transition deltas in S_BWD (seed-from-first-delta,
    -- ascending transition index).
    --   TRUE (and EXACT_LOGMAP=false) => reduce each x-set with a BALANCED
    -- binary max-TREE instead of the ~7-deep serial fold (the path-(2) lever,
    -- design.md 2a). In Max-Log-MAP mode maxstar degenerates to plain imax,
    -- which is ASSOCIATIVE, so the tree result is BIT-IDENTICAL to the serial
    -- fold -> the existing golden vectors stay byte-identical. The
    -- gamma/sat_add front of the fold (the 16 delta computations) is unchanged.
    -- CRITICAL: when EXACT_LOGMAP=true the tree is FORCIBLY DISABLED (the
    -- non-associative max* seed-from-first order is a pinned bit-exact
    -- contract, design.md 4 of the M1 change), so the effective predicate is
    -- (BAL_TREE_FOLD and not EXACT_LOGMAP).
    BAL_TREE_FOLD : boolean := false;
    -- ===================================================================
    -- PIPE_DFOLD (add-fpga-decoder-recurrence-pipelining, stage 1c task 1.1)
    -- ===================================================================
    -- Default FALSE => the S_BWD extrinsic path is SINGLE-CYCLE: at column
    -- kidx the alpha read + 16-delta sat_add front + gather + fold (serial or
    -- tree) + sat_sub all happen in the SAME cycle that emits x_e(kidx). This
    -- long feed-forward cone (alpha read -> sat_add front -> | -> tree/fold ->
    -- sat_sub -> xe_r) is path (2), the S_BWD limiter (design.md 2c).
    --   TRUE => PIPELINE the delta-fold across TWO cycles, cutting that cone at
    -- its midpoint. STAGE A (cycle k): compute the 16 deltas and gather
    -- d0buf/d1buf exactly as today, then REGISTER them (d0_r/d1_r) along with a
    -- 1-cycle-delayed output-valid (dfold_v_r) and the column-0 last flag
    -- (dfold_ol_r). STAGE B (cycle k+1): reduce the REGISTERED d0_r/d1_r (same
    -- serial-fold/tree predicate) -> xe_r, asserting ov from dfold_v_r and ol
    -- from dfold_ol_r. The beta recurrence keeps its per-cycle cadence
    -- (UNCHANGED -- it is independent of the fold output); only the x_e/ov/ol
    -- OUTPUT STREAM shifts ONE cycle later. The decoded x_e VALUES are
    -- IDENTICAL to the unpipelined core (pure timing/latency change), so the
    -- golden vectors stay byte-identical: a uniform +1-cycle latency with the
    -- SAME beat count (N) and SAME out_last alignment (logical column 0) is
    -- transparent to the value-sequence compare and to turbo_decoder_top's
    -- reverse-stream down-counter capture. END-OF-SWEEP DRAIN: because column
    -- 0's stage-A lands the cycle kidx=0 is processed, its x_e emerges the
    -- NEXT cycle, so a one-cycle S_BWD_DRAIN state emits the final registered
    -- x_e/ov/ol (ol from dfold_ol_r) before S_DONE. Total beats stay exactly
    -- N = K+3, done still pulses once. ORTHOGONAL to ANCHOR_NORM/BAL_TREE_FOLD/
    -- EXACT_LOGMAP (it only re-times the existing fold; the fold itself and the
    -- max* correction are unchanged).
    PIPE_DFOLD : boolean := false
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;                          -- sync, active-high
    start     : in  std_logic;                          -- latch K, begin load
    k_in      : in  std_logic_vector(W_K-1 downto 0);   -- block length K
    -- load phase: K+3 cycles of (x_a, z_a), already W_IN-quantized codes
    in_valid  : in  std_logic;
    x_a_in    : in  std_logic_vector(W_IN-1 downto 0);
    z_a_in    : in  std_logic_vector(W_IN-1 downto 0);
    -- output phase: K+3 cycles of extrinsic LLR codes
    out_valid : out std_logic;
    out_last  : out std_logic;
    x_e_out   : out std_logic_vector(W_XE-1 downto 0);
    -- status
    busy      : out std_logic;
    done      : out std_logic                           -- one-cycle pulse
  );
end entity constituent_decoder;

architecture rtl of constituent_decoder is

  constant STATES : integer := 8;

  -- Saturation bounds.
  constant AB_MIN : integer := -(2**(W_AB-1));      -- = MIN_SENT = -16384
  constant AB_MAX : integer :=  (2**(W_AB-1)) - 1;  -- = +16383
  constant DE_MIN : integer := -(2**(W_DELTA-1));
  constant DE_MAX : integer :=  (2**(W_DELTA-1)) - 1;
  constant XE_MIN : integer := -(2**(W_XE-1));
  constant XE_MAX : integer :=  (2**(W_XE-1)) - 1;
  constant MIN_SENT : integer := AB_MIN;

  -- Trellis (1..8 state indexing kept; arrays 0..15 for the 16 trans).
  -- alpha aggregation: for next-state s, the two incoming (from-state,
  -- trans-index) pairs, ascending trans-index (matches into_state{} in .m).
  type pair_t is array (0 to 1) of integer;
  type state_pairs_t is array (1 to STATES) of pair_t;
  -- from-state of the two incoming transitions per next-state
  constant A_FROM : state_pairs_t := (
    1 => (1, 2), 2 => (4, 3), 3 => (5, 6), 4 => (8, 7),
    5 => (2, 1), 6 => (3, 4), 7 => (6, 5), 8 => (7, 8));
  -- transition index (1..16) of the two incoming transitions per next-state
  constant A_TRAN : state_pairs_t := (
    1 => (1, 10), 2 => (4, 11), 3 => (5, 14), 4 => (8, 15),
    5 => (2,  9), 6 => (3, 12), 7 => (6, 13), 8 => (7, 16));
  -- beta aggregation: for state s, the two outgoing (to-state, trans-index)
  -- pairs, ascending trans-index (matches outof_state{} in .m).
  constant B_TO : state_pairs_t := (
    1 => (1, 5), 2 => (5, 1), 3 => (6, 2), 4 => (2, 6),
    5 => (3, 7), 6 => (7, 3), 7 => (8, 4), 8 => (4, 8));
  constant B_TRAN : state_pairs_t := (
    1 => (1,  9), 2 => (2, 10), 3 => (3, 11), 4 => (4, 12),
    5 => (5, 13), 6 => (6, 14), 7 => (7, 15), 8 => (8, 16));

  -- For the extrinsic / delta sweep: per transition (1..16) the from-state,
  -- to-state, x-bit and z-bit (whether gamma_z is -z or 0).
  type intvec16 is array (1 to 16) of integer;
  type bitvec16 is array (1 to 16) of std_logic;
  constant T_FROM : intvec16 := (
    1=>1, 2=>2, 3=>3, 4=>4, 5=>5, 6=>6, 7=>7, 8=>8,
    9=>1,10=>2,11=>3,12=>4,13=>5,14=>6,15=>7,16=>8);
  constant T_TO : intvec16 := (
    1=>1, 2=>5, 3=>6, 4=>2, 5=>3, 6=>7, 7=>8, 8=>4,
    9=>5,10=>1,11=>2,12=>6,13=>7,14=>3,15=>4,16=>8);
  constant T_XBIT : bitvec16 := (
    1=>'0',2=>'0',3=>'0',4=>'0',5=>'0',6=>'0',7=>'0',8=>'0',
    9=>'1',10=>'1',11=>'1',12=>'1',13=>'1',14=>'1',15=>'1',16=>'1');
  constant T_ZBIT : bitvec16 := (
    1=>'0',2=>'0',3=>'1',4=>'1',5=>'1',6=>'1',7=>'0',8=>'0',
    9=>'1',10=>'1',11=>'0',12=>'0',13=>'0',14=>'0',15=>'1',16=>'1');

  -- Metric working type: an 8-state alpha/beta column as scalar integers.
  type state_vec is array (1 to STATES) of integer;

  -- The two extrinsic x-sets each have exactly STATES (=8) transition deltas
  -- (x=0 -> transitions 1..8, x=1 -> transitions 9..16). delta8_t buffers one
  -- such set so the BAL_TREE_FOLD path can reduce it as a balanced max-tree.
  type delta8_t is array (1 to STATES) of integer;

  -- ===== M4K-inferable memories (write lifted to the mem process; sync
  -- read; ramstyle="M4K"). =====
  -- alpha_mem: one wide packed word per column (STATES*W_AB = 120 bits),
  -- depth N_MAX. Packed/unpacked via pack_col/unpack_col so the whole prior
  -- column is one M4K access. xa_mem/za_mem: W_IN-bit words, depth N_MAX.
  constant W_COL : integer := STATES * W_AB;      -- packed alpha column width
  type alpha_mem_t is array (0 to N_MAX-1) of std_logic_vector(W_COL-1 downto 0);
  type in_mem_t    is array (0 to N_MAX-1) of std_logic_vector(W_IN-1 downto 0);
  signal alpha_mem : alpha_mem_t := (others => (others => '0'));
  signal xa_mem    : in_mem_t    := (others => (others => '0'));
  signal za_mem    : in_mem_t    := (others => (others => '0'));

  -- Pin Cyclone-II block-RAM intent (M4K is the only flavour). The
  -- structural fix (write in the mem process, registered read) is what makes
  -- these infer; the attribute guards intent so a future edit that re-buries
  -- a write fails loudly rather than silently reverting to LE registers.
  attribute ramstyle : string;
  attribute ramstyle of alpha_mem : signal is "M4K";
  attribute ramstyle of xa_mem    : signal is "M4K";
  attribute ramstyle of za_mem    : signal is "M4K";

  -- Pack/unpack an 8-state integer column to/from the 120-bit M4K word.
  function pack_col(c : state_vec) return std_logic_vector is
    variable v : std_logic_vector(W_COL-1 downto 0);
  begin
    for s in 1 to STATES loop
      v((s-1)*W_AB + W_AB-1 downto (s-1)*W_AB) :=
        std_logic_vector(to_signed(c(s), W_AB));
    end loop;
    return v;
  end function;

  function unpack_col(v : std_logic_vector) return state_vec is
    variable c : state_vec;
  begin
    for s in 1 to STATES loop
      c(s) := to_integer(signed(v((s-1)*W_AB + W_AB-1 downto (s-1)*W_AB)));
    end loop;
    return c;
  end function;

  -- ---- Memory-process control (FSM drives these; never the arrays). ----
  -- alpha write port
  signal a_we    : std_logic := '0';
  signal a_waddr : integer range 0 to N_MAX-1 := 0;
  signal a_wdata : std_logic_vector(W_COL-1 downto 0) := (others => '0');
  -- alpha registered read port (used by the backward delta sweep)
  signal a_raddr : integer range 0 to N_MAX-1 := 0;
  signal a_rd    : std_logic_vector(W_COL-1 downto 0) := (others => '0');
  -- xa/za write port (shared address/we; two data lanes)
  signal in_we    : std_logic := '0';
  signal in_waddr : integer range 0 to N_MAX-1 := 0;
  signal xa_wdata : std_logic_vector(W_IN-1 downto 0) := (others => '0');
  signal za_wdata : std_logic_vector(W_IN-1 downto 0) := (others => '0');
  -- xa/za registered read port (used by the backward sweep)
  signal in_raddr : integer range 0 to N_MAX-1 := 0;
  signal xa_rd    : std_logic_vector(W_IN-1 downto 0) := (others => '0');
  signal za_rd    : std_logic_vector(W_IN-1 downto 0) := (others => '0');

  -- Forwarded (registered) column that keeps the forward sweep
  -- read-bubble-free: alpha_prev = the column just computed (= alpha(:,k-1)
  -- for the next forward step). The forward gamma at step k uses the inputs at
  -- column k-1, read from xa/za RAM with the same 2-edge latency as the
  -- backward path: in_raddr is issued two steps ahead (step k issues col k+1,
  -- consumed at step k+2). The first two steps (k=1 -> col 0, k=2 -> col 1)
  -- precede the RAM-read pipeline fill, so cols 0/1 inputs are forwarded in
  -- registers captured during the load. fcnt counts the forwarded steps left.
  signal alpha_prev : state_vec := (others => 0);
  signal xq0, zq0 : integer := 0;   -- inputs at column 0 (forwarded)
  signal xq1, zq1 : integer := 0;   -- inputs at column 1 (forwarded)
  signal fcnt     : integer range 0 to 2 := 0;

  -- beta is computed on the fly during the backward sweep; only the
  -- "next" column (k+1) is needed at a time.
  signal beta_cur : state_vec;

  -- Backward read latency (FSM-registered address -> mem-registered data =
  -- TWO clock edges). The backward read addresses are issued two cycles ahead
  -- of consumption: column Nr-1 in the final S_FWD step, Nr-2 in S_BWD_PRIME,
  -- and column kidx-2 in each S_BWD step, so a_rd/xa_rd/za_rd present column
  -- kidx exactly when S_BWD consumes it. Only alpha(:,Nr-1) cannot come from
  -- RAM in time -- its read is issued the same cycle it is written (a
  -- read-during-write of the fresh word), so it is forwarded in alpha_l1. All
  -- inputs and the remaining alpha columns read cleanly from RAM.
  signal alpha_l1  : state_vec := (others => 0);   -- forwarded alpha(:,Nr-1)
  signal bwd_first : std_logic := '0';             -- first backward column?

  -- S_BWD_DRAIN: the PIPE_DFOLD-only drain beat. With the +1-cycle fold
  -- latency, column 0's stage-A is computed the cycle kidx=0 is processed, so
  -- its x_e/ov/ol emerge one cycle later -- this state emits that final beat
  -- (with ol from dfold_ol_r) before S_DONE. When PIPE_DFOLD=false the FSM
  -- never enters it (S_BWD goes straight to S_DONE as before).
  type state_t is (S_IDLE, S_LOAD, S_FWD, S_BWD_PRIME, S_BWD, S_BWD_DRAIN, S_DONE);
  signal st   : state_t := S_IDLE;
  signal Nr   : integer range 0 to N_MAX := 0;   -- N = K+3
  signal kidx : integer range 0 to N_MAX := 0;   -- step counter

  signal ov, ol, bsy, dn : std_logic := '0';
  signal xe_r : integer := 0;

  -- PIPE_DFOLD pipeline registers (stage A -> stage B). When PIPE_DFOLD=false
  -- these are never written/read on the bit-exact path; synthesis prunes them.
  --   d0_r/d1_r  : the gathered x=0 / x=1 transition deltas registered in
  --                stage A (cycle k), reduced in stage B (cycle k+1).
  --   dfold_v_r  : stage-A produced a valid column this cycle (-> stage B emits
  --                ov next cycle). Cleared at sweep start so the first stage-B
  --                cycle (which has no prior column) emits nothing.
  --   dfold_ol_r : the registered out_last condition for that column (was it
  --                kidx=0) -> drives ol in stage B.
  signal d0_r, d1_r   : delta8_t := (others => 0);
  signal dfold_v_r    : std_logic := '0';
  signal dfold_ol_r   : std_logic := '0';

  -- Saturating helpers (scalar, signed integer, clamp - no wrap).
  function sat_add(a, b, lo, hi : integer) return integer is
    variable s : integer;
  begin
    s := a + b;
    if s > hi then return hi;
    elsif s < lo then return lo;
    else return s; end if;
  end function;

  function sat_sub(a, b, lo, hi : integer) return integer is
    variable s : integer;
  begin
    s := a - b;
    if s > hi then return hi;
    elsif s < lo then return lo;
    else return s; end if;
  end function;

  function imax(a, b : integer) return integer is
  begin
    if a >= b then return a; else return b; end if;
  end function;

  -- ===================================================================
  -- Exact-Log-MAP correction LUT (add-fpga-decoder-exact-log-map, §3).
  -- ===================================================================
  -- corr_code(dcode) = round( ln(1 + e^-(dcode * 2^-F_in)) * 2^F_in ),
  -- dcode = 0 .. LUT_D-1, generated at F_in=4. Byte-identical to the
  -- table built by build_correction_lut(56,4) in
  -- scripts/fixedpoint_constituent_decoder_logmap.m (anchors design.md §3:
  -- 0->11,1->11,2->10,4->9,6->8,9->7,12->6,15->5,18->4,23->3,31->2,55->1).
  -- corr_code(56)=0 and flat-0 beyond, so saturating the INDEX to LUT_D-1 is
  -- exact. Values in 0..11 (4-bit). Realized as a small case/ROM in logic
  -- (56 x 4 = 224 bits): NO M4K -- well below the M4K granularity.
  constant LUT_D    : integer := 56;     -- depth (design.md §3)
  constant LUT_IMAX : integer := LUT_D - 1;   -- index saturation = 55
  type lut_t is array (0 to LUT_D-1) of integer range 0 to 11;
  constant CORR_LUT : lut_t := (
    11, 11, 10, 10,  9,  9,  8,  8,
     8,  7,  7,  7,  6,  6,  6,  5,
     5,  5,  4,  4,  4,  4,  4,  3,
     3,  3,  3,  3,  3,  2,  2,  2,
     2,  2,  2,  2,  2,  2,  1,  1,
     1,  1,  1,  1,  1,  1,  1,  1,
     1,  1,  1,  1,  1,  1,  1,  1);

  -- 2-way Jacobian max: max(a,b) + corr_code(sat(|a-b|)), saturating into
  -- [lo,hi]. When EXACT_LOGMAP=false the correction is identically 0 so this
  -- is exactly imax(a,b) clamped (== imax(a,b) for in-range operands) -- the
  -- Max-Log-MAP superset. The LUT/adder constant-folds away in the default
  -- build. a, b are integer LSB codes on the same F_in grid (design.md §2/§3).
  function maxstar(a, b, lo, hi : integer) return integer is
    variable mx   : integer;
    variable d    : integer;
    variable corr : integer;
  begin
    mx := imax(a, b);
    if not EXACT_LOGMAP then
      return mx;                          -- plain max (default, bit-exact)
    end if;
    d := abs(a - b);
    if d > LUT_IMAX then
      d := LUT_IMAX;                      -- saturate the INDEX (LUT flat-0 above)
    end if;
    corr := CORR_LUT(d);
    return sat_add(mx, corr, lo, hi);     -- +corr is a saturating add
  end function;

  -- Balanced 3-level binary max-tree over the 8 deltas of one x-set
  -- (BAL_TREE_FOLD path, design.md §2a). Uses plain imax: this is ONLY called
  -- when EXACT_LOGMAP=false (guarded at the call site), where imax is
  -- associative, so the tree value is BIT-IDENTICAL to the serial left-fold
  -- of maxstar (= imax) over the same 8 elements. Depth is ceil(log2 8) = 3
  -- (vs the 7-deep serial fold), roughly halving the S_BWD fold path.
  function tree_max8(d : delta8_t) return integer is
    variable l1 : integer;   -- one level-1 node
    variable a01, a23, a45, a67 : integer;   -- level-1 results
    variable b03, b47 : integer;             -- level-2 results
  begin
    a01 := imax(d(1), d(2));
    a23 := imax(d(3), d(4));
    a45 := imax(d(5), d(6));
    a67 := imax(d(7), d(8));
    b03 := imax(a01, a23);
    b47 := imax(a45, a67);
    l1  := imax(b03, b47);
    return l1;
  end function;

  -- Reduce one x-set's 8 deltas to its max (the extrinsic fold body, factored
  -- so the single-cycle path and the PIPE_DFOLD stage-B share ONE definition).
  -- Predicate identical to the inline fold: BAL_TREE_FOLD (and only when
  -- EXACT_LOGMAP=false) uses the associative balanced max-tree (bit-identical
  -- to the serial fold there); otherwise the SEQUENTIAL LEFT FOLD seeded from
  -- the first delta in ascending transition index (the pinned max* order).
  function fold8(d : delta8_t) return integer is
    variable mx : integer;
  begin
    if BAL_TREE_FOLD and not EXACT_LOGMAP then
      return tree_max8(d);
    end if;
    mx := d(1);                          -- seed from the first delta
    for i in 2 to STATES loop
      mx := maxstar(mx, d(i), DE_MIN, DE_MAX);
    end loop;
    return mx;
  end function;

  -- gamma(t) = -x*xbit(t) - z*zbit(t), in W_GAMMA (no sat needed:
  -- |gamma| <= |x|+|z| < 2^W_IN <= 2^(W_GAMMA-1)).
  function gamma_of(t : integer; x, z : integer) return integer is
    variable g : integer := 0;
  begin
    if T_XBIT(t) = '1' then g := g - x; end if;
    if T_ZBIT(t) = '1' then g := g - z; end if;
    return g;
  end function;

  -- gamma_z(t) = -z*zbit(t).
  function gammaz_of(t : integer; z : integer) return integer is
  begin
    if T_ZBIT(t) = '1' then return -z; else return 0; end if;
  end function;

begin
  out_valid <= ov;
  out_last  <= ol;
  x_e_out   <= std_logic_vector(to_signed(xe_r, W_XE));
  busy      <= bsy;
  done      <= dn;

  -- ---------------------------------------------------------------------------
  -- Dedicated memory process: the alpha/xa/za array writes and registered reads
  -- live here ONLY, with NO synchronous reset on the array bodies (the M4K
  -- write-port template). The FSM drives the write controls
  -- (a_we/a_waddr/a_wdata, in_we/in_waddr/xa_wdata/za_wdata) and the read
  -- addresses (a_raddr/in_raddr); it never touches the arrays directly. Each
  -- array has exactly one write port and one registered read port (1W/1R SDP).
  -- ---------------------------------------------------------------------------
  mem : process (clk)
  begin
    if rising_edge(clk) then
      -- alpha: single write port (col-0 init and the forward per-column write
      -- both arrive via a_we/a_waddr/a_wdata), one registered read port.
      if a_we = '1' then
        alpha_mem(a_waddr) <= a_wdata;
      end if;
      a_rd <= alpha_mem(a_raddr);

      -- xa/za: single shared write port (load), registered reads.
      if in_we = '1' then
        xa_mem(in_waddr) <= xa_wdata;
        za_mem(in_waddr) <= za_wdata;
      end if;
      xa_rd <= xa_mem(in_raddr);
      za_rd <= za_mem(in_raddr);
    end if;
  end process mem;

  process (clk)
    variable new_a   : state_vec;
    variable new_b   : state_vec;
    variable m       : integer;
    variable c1, c2  : integer;
    variable t1, t2  : integer;
    variable xq, zq  : integer;
    variable ab_sum  : integer;
    variable delta   : integer;
    variable d0buf   : delta8_t;   -- gathered x=0 deltas (fold/register input)
    variable d1buf   : delta8_t;   -- gathered x=1 deltas (fold/register input)
    variable n0, n1  : integer;    -- fill counters for the two x-sets
  begin
    if rising_edge(clk) then
      ov <= '0';
      ol <= '0';
      dn <= '0';
      -- Memory write-enables default low; pulse only on the intended cycle.
      a_we  <= '0';
      in_we <= '0';

      if rst = '1' then
        st  <= S_IDLE;
        bsy <= '0';
      else
        case st is

          when S_IDLE =>
            if start = '1' then
              Nr   <= to_integer(unsigned(k_in)) + 3;   -- N = K+3
              kidx <= 0;
              bsy  <= '1';
              st   <= S_LOAD;
            end if;

          -- LOAD: capture K+3 (x_a, z_a) quantized codes into xa/za RAM via
          -- the single shared write port. At the last column, also issue the
          -- alpha col-0 init write (the +/-inf sentinel column) through the
          -- alpha write port -- a top-level memory write, NOT a reset clear.
          when S_LOAD =>
            if in_valid = '1' then
              in_we    <= '1';
              in_waddr <= kidx;
              xa_wdata <= x_a_in;
              za_wdata <= z_a_in;
              -- Forward columns 0 and 1 inputs for the first two forward steps
              -- (their RAM reads cannot land before the pipeline fills).
              if kidx = 0 then
                xq0 <= to_integer(signed(x_a_in));
                zq0 <= to_integer(signed(z_a_in));
              elsif kidx = 1 then
                xq1 <= to_integer(signed(x_a_in));
                zq1 <= to_integer(signed(z_a_in));
              end if;
              if kidx = Nr - 1 then
                -- init alpha column 0: state 1 = 0, others = MIN_SENT.
                for s in 1 to STATES loop
                  if s = 1 then new_a(s) := 0; else new_a(s) := MIN_SENT; end if;
                end loop;
                a_we    <= '1';
                a_waddr <= 0;
                a_wdata <= pack_col(new_a);
                -- Forward the just-built column 0 so the first forward step
                -- (computing column 1) reads it from alpha_prev, not RAM.
                alpha_prev <= new_a;
                fcnt <= 2;        -- steps k=1,2 use forwarded col 0,1 inputs
                kidx <= 1;        -- forward recursion fills columns 1..N-1
                st   <= S_FWD;
              else
                kidx <= kidx + 1;
              end if;
            end if;

          -- FORWARD: alpha(:,k) from alpha(:,k-1) (= alpha_prev, forwarded)
          -- and gamma(:,k-1). One trellis column per cycle. Mirrors the .m
          -- loop k=2..N (here 0-indexed k=1..N-1, gamma at column k-1).
          -- Inputs at column k-1: steps k=1,2 use the forwarded xq0/xq1 (their
          -- RAM reads have not landed yet); steps k>=3 use xa_rd/za_rd, the
          -- registered RAM read issued two steps earlier (in_raddr <= k+1 below
          -- presents col k+1 for step k+2, matching the 2-edge latency).
          when S_FWD =>
            if fcnt = 2 then
              xq := xq0;  zq := zq0;            -- step k=1 -> col 0
            elsif fcnt = 1 then
              xq := xq1;  zq := zq1;            -- step k=2 -> col 1
            else
              xq := to_integer(signed(xa_rd));  -- step k>=3 -> col k-1 (RAM)
              zq := to_integer(signed(za_rd));
            end if;
            if fcnt > 0 then fcnt <= fcnt - 1; end if;
            -- 2-way max per next-state of (prev_alpha + gamma), saturating.
            for s in 1 to STATES loop
              t1 := A_TRAN(s)(0);
              t2 := A_TRAN(s)(1);
              c1 := sat_add(alpha_prev(A_FROM(s)(0)),
                            gamma_of(t1, xq, zq), AB_MIN, AB_MAX);
              c2 := sat_add(alpha_prev(A_FROM(s)(1)),
                            gamma_of(t2, xq, zq), AB_MIN, AB_MAX);
              -- 2-way max* (correction conditional on EXACT_LOGMAP; cand1 is
              -- the lower transition index, matching the .m into_state order).
              new_a(s) := maxstar(c1, c2, AB_MIN, AB_MAX);
            end loop;
            -- per-step normalization. Subtract a common per-step offset m from
            -- all 8 next-states (a bookkeeping shift -- NO correction,
            -- design.md §2). Default (ANCHOR_NORM=false): m = max over the 8
            -- states (the 8-way max tree). ANCHOR_NORM=true: m = state 1 (the
            -- anchor) -- output-equivalent (common offset cancels in x_e) but
            -- removes the max tree from the recurrence cone.
            if ANCHOR_NORM then
              m := new_a(1);
            else
              m := new_a(1);
              for s in 2 to STATES loop
                m := imax(m, new_a(s));
              end loop;
            end if;
            for s in 1 to STATES loop
              new_a(s) := sat_sub(new_a(s), m, AB_MIN, AB_MAX);
            end loop;
            -- Write column kidx to alpha RAM (for the backward re-read) and
            -- forward it for the NEXT forward step (no read bubble).
            a_we    <= '1';
            a_waddr <= kidx;
            a_wdata <= pack_col(new_a);
            alpha_prev <= new_a;

            if kidx = Nr - 1 then
              -- init beta at column N-1: state 1 = 0, others = MIN_SENT.
              for s in 1 to STATES loop
                if s = 1 then
                  new_b(s) := 0;
                else
                  new_b(s) := MIN_SENT;
                end if;
              end loop;
              beta_cur <= new_b;
              -- Backward sweep starts at the last column (= the column just
              -- computed). Forward its alpha in alpha_l1 (the RAM read of Nr-1
              -- would be a read-during-write of the just-written word). Issue
              -- the lead reads two cycles ahead: present column Nr-1 inputs to
              -- xa/za RAM now (consumed in the first S_BWD step) and the alpha
              -- read addr Nr-1 too (its data is the stale fresh word, unused;
              -- alpha_l1 covers column Nr-1).
              alpha_l1   <= new_a;
              bwd_first  <= '1';
              a_raddr    <= Nr - 1;
              in_raddr   <= Nr - 1;
              kidx       <= Nr - 1;
              st         <= S_BWD_PRIME;
            else
              -- Lead-by-two input prefetch: step k presents col k+1 so it is
              -- registered into xa_rd/za_rd for step k+2 (which needs col k+1).
              -- Bounded to the valid range; cols beyond Nr-2 are never read.
              if kidx + 1 <= Nr - 1 then
                in_raddr <= kidx + 1;
              end if;
              kidx <= kidx + 1;
            end if;

          -- BACKWARD PRIME: the column Nr-1 reads were issued in S_FWD (data
          -- lands at THIS edge -> valid for the first S_BWD step). Issue the
          -- next lead reads here for column Nr-2 (consumed in the SECOND S_BWD
          -- step, two cycles from now). Guard the address against underflow.
          when S_BWD_PRIME =>
            if Nr >= 2 then
              a_raddr  <= Nr - 2;
              in_raddr <= Nr - 2;
            end if;
            -- Prime the PIPE_DFOLD pipeline empty: the FIRST S_BWD cycle's
            -- stage B has no prior column to emit, so its valid must be low.
            dfold_v_r <= '0';
            st <= S_BWD;

          -- BACKWARD + EXTRINSIC: at column kidx use the stored alpha(:,kidx)
          -- (a_rd, registered) and the current beta(:,kidx) (beta_cur) to emit
          -- x_e(kidx); then compute beta(:,kidx-1). Emits kidx = N-1 down to 0.
          -- a_rd/xa_rd/za_rd hold column kidx (issued the prior cycle).
          when S_BWD =>
            xq := to_integer(signed(xa_rd));
            zq := to_integer(signed(za_rd));

            -- ===== PIPE_DFOLD STAGE B (emit the PREVIOUS column's x_e) =====
            -- Reduce the deltas registered in the prior cycle's stage A and
            -- emit x_e one cycle late. dfold_v_r gates the very first S_BWD
            -- cycle (which has no prior column) to emit nothing. Stage B runs
            -- BEFORE stage A's writes below, but they touch disjoint targets
            -- (xe_r/ov/ol here; d0_r/d1_r/dfold_*_r in stage A), so order is
            -- immaterial. Default (PIPE_DFOLD=false): this block is dead.
            if PIPE_DFOLD then
              if dfold_v_r = '1' then
                xe_r <= sat_sub(fold8(d0_r), fold8(d1_r), XE_MIN, XE_MAX);
                ov   <= '1';
                ol   <= dfold_ol_r;
              end if;
            end if;

            -- ---- extrinsic at column kidx (uses beta_cur = beta(:,kidx)).
            -- For the first backward column (just written) use the forwarded
            -- alpha_l1; thereafter the registered RAM read a_rd is clean.
            if bwd_first = '1' then
              new_a := alpha_l1;
            else
              new_a := unpack_col(a_rd);        -- stored alpha(:,kidx)
            end if;
            bwd_first <= '0';
            -- Compute the 16 transition deltas (the gamma/sat_add FRONT of the
            -- fold, UNCHANGED) and gather each x-set's 8 deltas into d0buf/d1buf
            -- in ascending transition index. d0buf/d1buf(1..8) hold the x=0 /
            -- x=1 deltas in exactly the order the serial fold visits them.
            n0 := 0;
            n1 := 0;
            for t in 1 to 16 loop
              ab_sum := sat_add(new_a(T_FROM(t)),
                                beta_cur(T_TO(t)), DE_MIN, DE_MAX);
              delta  := sat_add(ab_sum, gammaz_of(t, zq), DE_MIN, DE_MAX);
              if T_XBIT(t) = '0' then
                n0 := n0 + 1;
                d0buf(n0) := delta;
              else
                n1 := n1 + 1;
                d1buf(n1) := delta;
              end if;
            end loop;
            -- ===== EXTRINSIC FOLD =====
            -- PIPE_DFOLD=false (default): single-cycle -- reduce the just-built
            -- d0buf/d1buf (serial fold or balanced tree, via fold8) and emit
            -- x_e(kidx) THIS cycle. Byte-identical to the prior inline fold.
            --   PIPE_DFOLD=true: STAGE A -- only REGISTER the gathered deltas
            -- (d0_r/d1_r) + a valid/last flag; the reduce + emit happen next
            -- cycle in stage B above. The long alpha-read -> sat_add front ->
            -- | -> fold -> sat_sub cone is thus cut at the fold midpoint.
            if PIPE_DFOLD then
              d0_r       <= d0buf;
              d1_r       <= d1buf;
              dfold_v_r  <= '1';
              if kidx = 0 then
                dfold_ol_r <= '1';
              else
                dfold_ol_r <= '0';
              end if;
            else
              xe_r <= sat_sub(fold8(d0buf), fold8(d1buf), XE_MIN, XE_MAX);
              ov   <= '1';
              if kidx = 0 then
                ol <= '1';
              end if;
            end if;

            -- ---- compute beta(:,kidx-1) for the next cycle (if any).
            -- gamma uses the input at column kidx (= xq/zq just read).
            if kidx > 0 then
              for s in 1 to STATES loop
                t1 := B_TRAN(s)(0);
                t2 := B_TRAN(s)(1);
                c1 := sat_add(beta_cur(B_TO(s)(0)),
                              gamma_of(t1, xq, zq), AB_MIN, AB_MAX);
                c2 := sat_add(beta_cur(B_TO(s)(1)),
                              gamma_of(t2, xq, zq), AB_MIN, AB_MAX);
                -- 2-way max* (correction conditional on EXACT_LOGMAP; cand1 is
                -- the lower transition index, matching the .m outof_state order).
                new_b(s) := maxstar(c1, c2, AB_MIN, AB_MAX);
              end loop;
              -- per-step normalization (same anchor/max choice as S_FWD).
              if ANCHOR_NORM then
                m := new_b(1);
              else
                m := new_b(1);
                for s in 2 to STATES loop
                  m := imax(m, new_b(s));
                end loop;
              end if;
              for s in 1 to STATES loop
                new_b(s) := sat_sub(new_b(s), m, AB_MIN, AB_MAX);
              end loop;
              beta_cur <= new_b;
              -- Issue the lead reads for column kidx-2 (consumed two S_BWD
              -- steps from now, matching the 2-edge registered-read latency).
              -- Guard against underflow near the end of the sweep (those words
              -- are never consumed).
              if kidx >= 2 then
                a_raddr  <= kidx - 2;
                in_raddr <= kidx - 2;
              end if;
              kidx <= kidx - 1;
            else
              -- kidx = 0: column 0's stage work is done this cycle.
              -- PIPE_DFOLD=false: x_e(0) was emitted THIS cycle -> done.
              -- PIPE_DFOLD=true: x_e(0) is still in the stage-A registers
              -- (dfold_v_r='1', dfold_ol_r='1'); drain it one more cycle.
              if PIPE_DFOLD then
                st <= S_BWD_DRAIN;
              else
                st <= S_DONE;
              end if;
            end if;

          -- BACKWARD DRAIN (PIPE_DFOLD only): emit the final registered x_e
          -- (column 0) with out_last, then finish. This makes the pipelined
          -- sweep emit EXACTLY N beats (Nr-1 .. 0) with out_last on column 0,
          -- identical in count + alignment to the unpipelined sweep -- only
          -- shifted one cycle. The beta recurrence has already terminated
          -- (kidx hit 0), so nothing else runs here.
          when S_BWD_DRAIN =>
            xe_r <= sat_sub(fold8(d0_r), fold8(d1_r), XE_MIN, XE_MAX);
            ov   <= '1';
            ol   <= dfold_ol_r;          -- '1' (the column-0 last flag)
            dfold_v_r <= '0';
            st   <= S_DONE;

          when S_DONE =>
            bsy <= '0';
            dn  <= '1';
            st  <= S_IDLE;

        end case;
      end if;
    end if;
  end process;
end architecture rtl;
