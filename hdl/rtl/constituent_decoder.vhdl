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
-- design.md §5 (sliding-window/BRAM is roadmap M2). Latency ~3*(K+3)
-- cycles: load K+3, forward K+3, backward+extrinsic K+3.
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
    N_MAX   : integer := 6147    -- max N = K+3 = 6144+3
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

  -- Metric memories.
  type state_vec is array (1 to STATES) of integer;
  type ab_mem_t  is array (0 to N_MAX-1) of state_vec;
  signal alpha_mem : ab_mem_t;            -- full-block alpha storage
  -- input LLR storage (quantized integer codes).
  type in_mem_t is array (0 to N_MAX-1) of integer;
  signal xa_mem : in_mem_t;
  signal za_mem : in_mem_t;

  -- beta is computed on the fly during the backward sweep; only the
  -- "next" column (k+1) is needed at a time.
  signal beta_cur : state_vec;

  type state_t is (S_IDLE, S_LOAD, S_FWD, S_BWD, S_DONE);
  signal st   : state_t := S_IDLE;
  signal Nr   : integer range 0 to N_MAX := 0;   -- N = K+3
  signal kidx : integer range 0 to N_MAX := 0;   -- step counter

  signal ov, ol, bsy, dn : std_logic := '0';
  signal xe_r : integer := 0;

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

  process (clk)
    variable new_a   : state_vec;
    variable new_b   : state_vec;
    variable m       : integer;
    variable c1, c2  : integer;
    variable t1, t2  : integer;
    variable xq, zq  : integer;
    variable ab_sum  : integer;
    variable delta   : integer;
    variable max0    : integer;
    variable max1    : integer;
  begin
    if rising_edge(clk) then
      ov <= '0';
      ol <= '0';
      dn <= '0';

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

          -- LOAD: capture K+3 (x_a, z_a) quantized codes.
          when S_LOAD =>
            if in_valid = '1' then
              xa_mem(kidx) <= to_integer(signed(x_a_in));
              za_mem(kidx) <= to_integer(signed(z_a_in));
              if kidx = Nr - 1 then
                -- init alpha column 0: state 1 = 0, others = MIN_SENT.
                for s in 1 to STATES loop
                  if s = 1 then
                    alpha_mem(0)(s) <= 0;
                  else
                    alpha_mem(0)(s) <= MIN_SENT;
                  end if;
                end loop;
                kidx <= 1;        -- forward recursion fills columns 1..N-1
                st   <= S_FWD;
              else
                kidx <= kidx + 1;
              end if;
            end if;

          -- FORWARD: alpha(:,k) from alpha(:,k-1) and gamma(:,k-1).
          -- One trellis column per cycle. Mirrors the .m loop k=2..N
          -- (here 0-indexed k=1..N-1, using gamma at column k-1).
          when S_FWD =>
            xq := xa_mem(kidx - 1);
            zq := za_mem(kidx - 1);
            -- 2-way max per next-state of (prev_alpha + gamma), saturating.
            for s in 1 to STATES loop
              t1 := A_TRAN(s)(0);
              t2 := A_TRAN(s)(1);
              c1 := sat_add(alpha_mem(kidx - 1)(A_FROM(s)(0)),
                            gamma_of(t1, xq, zq), AB_MIN, AB_MAX);
              c2 := sat_add(alpha_mem(kidx - 1)(A_FROM(s)(1)),
                            gamma_of(t2, xq, zq), AB_MIN, AB_MAX);
              new_a(s) := imax(c1, c2);
            end loop;
            -- per-step max-normalization (max over the 8 next-states).
            m := new_a(1);
            for s in 2 to STATES loop
              m := imax(m, new_a(s));
            end loop;
            for s in 1 to STATES loop
              alpha_mem(kidx)(s) <= sat_sub(new_a(s), m, AB_MIN, AB_MAX);
            end loop;

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
              kidx     <= Nr - 1;     -- backward sweep starts at last column
              st       <= S_BWD;
            else
              kidx <= kidx + 1;
            end if;

          -- BACKWARD + EXTRINSIC: at column k use the stored alpha(:,k)
          -- and the current beta(:,k) to emit x_e(k); then compute the
          -- beta(:,k-1) for the next cycle. Emits k = N-1 down to 0.
          when S_BWD =>
            xq := xa_mem(kidx);
            zq := za_mem(kidx);

            -- ---- extrinsic at column kidx (uses beta_cur = beta(:,kidx)).
            max0 := DE_MIN;
            max1 := DE_MIN;
            for t in 1 to 16 loop
              ab_sum := sat_add(alpha_mem(kidx)(T_FROM(t)),
                                beta_cur(T_TO(t)), DE_MIN, DE_MAX);
              delta  := sat_add(ab_sum, gammaz_of(t, zq), DE_MIN, DE_MAX);
              if T_XBIT(t) = '0' then
                max0 := imax(max0, delta);
              else
                max1 := imax(max1, delta);
              end if;
            end loop;
            xe_r <= sat_sub(max0, max1, XE_MIN, XE_MAX);
            ov   <= '1';
            if kidx = 0 then
              ol <= '1';
            end if;

            -- ---- compute beta(:,kidx-1) for the next cycle (if any).
            -- beta(s,k-1) = max over outgoing trans of (beta(to,k)+gamma).
            -- gamma uses the input at column k (= kidx), matching the .m
            -- (betas k uses gammas(:,k+1); here next col is kidx, current
            -- emit col is kidx so the gamma feeding beta(:,kidx-1) is the
            -- column-kidx gamma).
            if kidx > 0 then
              for s in 1 to STATES loop
                t1 := B_TRAN(s)(0);
                t2 := B_TRAN(s)(1);
                c1 := sat_add(beta_cur(B_TO(s)(0)),
                              gamma_of(t1, xq, zq), AB_MIN, AB_MAX);
                c2 := sat_add(beta_cur(B_TO(s)(1)),
                              gamma_of(t2, xq, zq), AB_MIN, AB_MAX);
                new_b(s) := imax(c1, c2);
              end loop;
              m := new_b(1);
              for s in 2 to STATES loop
                m := imax(m, new_b(s));
              end loop;
              for s in 1 to STATES loop
                new_b(s) := sat_sub(new_b(s), m, AB_MIN, AB_MAX);
              end loop;
              beta_cur <= new_b;
              kidx <= kidx - 1;
            else
              st  <= S_DONE;
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
