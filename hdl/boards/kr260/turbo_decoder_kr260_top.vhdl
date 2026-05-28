library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.turbo_decoder_golden_pkg.all;  -- GV_* on-chip golden vector (K=512)

-- AMD Kria KR260 (Zynq UltraScale+ xck26-sfvc784-2LV) board demo for the
-- iterative turbo decoder core turbo_decoder_top. PORTED from the DE2 wrapper
-- (hdl/boards/de2/turbo_decoder_de2_top.vhdl) — the verified self-check FSM,
-- err_cnt comparator, run-hold timer, and heartbeat counter are reused
-- VERBATIM. The DE2-specific glue (altpll IP, LCD/hex7seg, KEY input, LEDG/R
-- arrays) is stripped; this wrapper drives ONLY two LEDs and takes its clock
-- + reset from a minimal Zynq MPSoC PS block design instantiated below (the
-- canonical Kria PL-only clocking path — see design.md §3 option A).
--
-- The decoder core turbo_decoder_top is instantiated UNMODIFIED: K_MAX=512,
-- MAX_ITERATIONS=2 (matches GV_MAX_ITER), and all three recurrence-pipelining
-- levers ON (ANCHOR_NORM / BAL_TREE_FOLD / PIPE_DFOLD) — same as the DE2
-- 25 MHz build, bit-exact decoded bits, just at the K26 PL clock (100 MHz
-- target).
--
-- TWO-LED STATUS ENCODING (the user's constraint — only two LEDs visible):
--   LEDS(0)  "alive / well" :
--     - while RUNNING (run_hold window active OR no verdict yet) : BLINKS
--       at the heartbeat phase (~0.34 s at 100 MHz, hb_cnt(25)) so the user
--       sees that the design is clocked and the self-check is in flight;
--     - after a PASS verdict (and after run_hold elapsed) : SOLID '1';
--     - after a FAIL verdict : '0' (off).
--   LEDS(1)  "fail" :
--     - SOLID '1' only after a FAIL verdict; '0' otherwise.
--   The two-LED encoding is therefore unambiguous from across the room:
--     blink  = running ;
--     solid one LED on (LEDS(0)) = passed ;
--     solid other LED on (LEDS(1)) = failed ;
--     both off = power/clock problem (no heartbeat).
--
-- Single-shot per power-cycle for v1 (the user OK'd re-run by power-cycle —
-- the KR260 carrier has no convenient PL-side push-button to wire up for a
-- KEY0-style restart). The internal `restart` signal is therefore tied to
-- the PS reset (one assertion at power-up via proc_sys_reset_0) — it still
-- exists in the FSM, just driven from the system reset edge rather than a
-- user button. Adding a PMOD button later would only require driving
-- `restart` from that input.
--
-- I/O / verdict mapping (KR260-specific):
--   (from BD)  pl_clk0     100 MHz PS-sourced PL clock (zynq_ultra_ps_e
--                          pl_clk0, gated by the BD's proc_sys_reset)
--   (from BD)  pl_resetn0  active-LOW synchronous reset from proc_sys_reset
--   LEDS(0)              PASS-or-RUNNING (see encoding above) -> pin F8 LVCMOS18
--   LEDS(1)              FAIL                                  -> pin E8 LVCMOS18
--
-- The pin LOCs are pinned in the .xdc (kr260_carrier connection_map →
-- kr260_som part0_pins som240_1_d13/d14): F8 / E8, LVCMOS18.

entity turbo_decoder_kr260_top is
  generic (
    -- Core sizing. K_MAX matches the on-chip golden ROM (K=512); the core
    -- internally rounds up to N_MAX = K_MAX+3 = 515.
    K_MAX : integer := 512;
    -- Max iterations -- pinned to GV_MAX_ITER so the core's H = 2*MAX_ITER = 4
    -- matches the golden vector's half-iteration count exactly.
    MAX_ITERATIONS : integer := 2;
    -- TEST-ONLY fault-injection knob (identical semantics to the DE2 wrapper).
    -- Default -1 disables it -- the synthesized board behaviour is the real
    -- golden compare. A self-check TB sets it to a valid index (0..GV_K-1) to
    -- corrupt one expected bit and prove the comparator reaches FAIL.
    CORRUPT_IDX : integer := -1;
    -- TEST-ONLY override for the minimum RUNNING-display hold (in cycles).
    -- Default -1 keeps the real board window (~1.5 s on the PL clock). A TB
    -- sets it small so the verdict latches within the sim budget. The DE2
    -- wrapper carried this lever for its LCD; here it gates only the LED-0
    -- blink-vs-solid transition, but the lever is preserved for symmetry.
    RUN_HOLD_CYC_OVR : integer := -1;
    -- PL clock rate -- used to size run_hold_cycles. The BD presets the
    -- zynq_ultra_ps_e CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ to 100, so the
    -- default here matches; if the BD's PL clock is re-tuned the generic
    -- should track. (No bit-exact dependency on this value -- the decoded
    -- bits are clock-rate-independent.)
    CLK_HZ : integer := 100_000_000
  );
  port (
    -- The ONLY top-level ports are the two status LEDs. The PL clock and reset
    -- come from the instantiated BD wrapper below (which contains the Zynq
    -- MPSoC PS block design). The KR260 carrier has no top-level oscillator
    -- the PL can use without going through the PS, so there is no clock input
    -- pin to expose.
    LEDS : out std_logic_vector(1 downto 0)
  );
end entity turbo_decoder_kr260_top;

architecture rtl of turbo_decoder_kr260_top is

  -- Core-internal widths (mirror the DE2 wrapper -- explicit so the wrapper
  -- compiles standalone in GHDL with no need to import the core's defaults).
  constant W_EXT : integer := 12;
  constant W_K   : integer := 13;

  ----------------------------------------------------------------------------
  -- Component declarations.
  ----------------------------------------------------------------------------

  -- Block-design wrapper for the minimal Zynq MPSoC clocking block design.
  -- Generated by Vivado's `make_wrapper -files <bd>.bd -top -import` in the
  -- TCL build script. The BD contains:
  --   * zynq_ultra_ps_e_0   (PS block, K26 board preset, AXI disabled,
  --                          PL_CLK0 enabled at 100 MHz, no DDR app)
  --   * proc_sys_reset_0    (synchronizes pl_resetn0 to pl_clk0)
  -- Output ports: pl_clk0 (100 MHz to PL fabric) and pl_resetn0 (active-LOW
  -- synchronous reset). Both are BD output ports of the wrapper, NOT top-level
  -- pins -- the PS provides them internally.
  component kr260_clocking_wrapper is
    port (
      pl_clk0    : out std_logic;
      pl_resetn0 : out std_logic
    );
  end component;

  -- Iterative turbo decoder core. Same component decl as the DE2 wrapper;
  -- generics match (recurrence levers ON).
  component turbo_decoder_top is
    generic (
      W_IN    : integer := 9;
      W_GAMMA : integer := 10;
      W_AB    : integer := 15;
      W_DELTA : integer := 17;
      W_XE    : integer := 18;
      W_EXT   : integer := 12;
      W_ACC   : integer := 14;
      W_K     : integer := 13;
      K_MAX   : integer := 6144;
      MAX_ITERATIONS : integer := 8;
      ANCHOR_NORM    : boolean := false;
      BAL_TREE_FOLD  : boolean := false;
      PIPE_DFOLD     : boolean := false
    );
    port (
      clk       : in  std_logic;
      rst       : in  std_logic;
      in_start  : in  std_logic;
      k_in      : in  std_logic_vector(W_K-1 downto 0);
      da_valid  : in  std_logic;
      da1_in    : in  std_logic_vector(W_EXT-1 downto 0);
      da2_in    : in  std_logic_vector(W_EXT-1 downto 0);
      da3_in    : in  std_logic_vector(W_EXT-1 downto 0);
      out_valid : out std_logic;
      out_last  : out std_logic;
      c_out     : out std_logic;
      busy      : out std_logic;
      done      : out std_logic
    );
  end component;

  ----------------------------------------------------------------------------
  -- Clocking / reset (from the BD wrapper).
  ----------------------------------------------------------------------------
  signal clk        : std_logic;
  signal pl_resetn  : std_logic;
  signal rst_async  : std_logic;   -- active-HIGH internal reset = not pl_resetn
  -- One-shot restart pulse synthesized from the rst_async release edge. The
  -- DE2 wrapper had a KEY0 edge-detect; here the only restart event is the
  -- PS deasserting reset on power-up, so we synthesize a single pulse off
  -- that deassertion (one cycle wide on `clk`) -- the FSM then re-enters
  -- CH_RESET and the run-hold window reloads.
  signal pl_resetn_q  : std_logic_vector(1 downto 0) := (others => '0');
  signal pl_resetn_d  : std_logic := '0';   -- previous-cycle sync of pl_resetn
  signal restart      : std_logic;

  ----------------------------------------------------------------------------
  -- Self-check FSM (ported VERBATIM from the DE2 wrapper).
  ----------------------------------------------------------------------------
  type chk_state_t is (CH_RESET, CH_START, CH_LOAD, CH_RUN, CH_PASS, CH_FAIL);
  signal chk : chk_state_t := CH_RESET;

  -- Core interface signals.
  signal core_rst   : std_logic := '1';
  signal core_start : std_logic := '0';
  signal core_dav   : std_logic := '0';
  signal core_da1   : std_logic_vector(W_EXT-1 downto 0) := (others => '0');
  signal core_da2   : std_logic_vector(W_EXT-1 downto 0) := (others => '0');
  signal core_da3   : std_logic_vector(W_EXT-1 downto 0) := (others => '0');
  signal core_ov    : std_logic;
  signal core_ol    : std_logic;
  signal core_cout  : std_logic;
  signal core_busy  : std_logic;
  signal core_done  : std_logic;

  signal load_idx : integer range 0 to GV_N_COLS := 0;   -- next d_a column
  signal cmp_idx  : integer range 0 to GV_K := 0;         -- next expected c bit

  -- Status flags driven from the FSM.
  signal pass_f : std_logic := '0';
  signal fail_f : std_logic := '0';
  signal done_f : std_logic := '0';

  -- Output-bit error count (saturating). Ported from the DE2 wrapper; even
  -- though the KR260 demo doesn't display the count numerically, the count
  -- semantics are the verdict-gating condition (PASS iff err_cnt = 0 AND
  -- framing OK) -- so the comparator logic is kept VERBATIM.
  constant ERR_W   : integer := 10;
  constant ERR_MAX : integer := 999;
  signal err_cnt   : unsigned(ERR_W-1 downto 0) := (others => '0');
  signal frame_err : std_logic := '0';

  ----------------------------------------------------------------------------
  -- Heartbeat counter -- LED-0 blink while RUNNING. At 100 MHz, bit 25 of a
  -- free-running counter toggles every 2^25 / 1e8 ~ 0.336 s ~ ~3 Hz, the same
  -- visual rate as the DE2 wrapper's bit-22 heartbeat at 12.5 MHz (2^22 /
  -- 12.5e6 ~ 0.34 s). We pick bit 25 for the 100 MHz PL clock so the blink
  -- LOOKS the same as on the DE2. Counter width 27 gives margin.
  ----------------------------------------------------------------------------
  signal hb_cnt : unsigned(26 downto 0) := (others => '0');
  signal hb     : std_logic;            -- current heartbeat phase

  ----------------------------------------------------------------------------
  -- Minimum RUNNING-display window. The self-check latches its verdict in
  -- well under 1 ms (K=512, H=4, 100 MHz), so without a hold the brief
  -- blink-while-running phase would be invisible. The DE2 wrapper held this
  -- ~1.5 s for the LCD; we re-use it here to keep LED-0 in BLINK mode for at
  -- least the same ~1.5 s after a power-up restart, so the user always sees
  -- the running pulse before the solid PASS appears.
  ----------------------------------------------------------------------------
  function run_hold_cycles return integer is
  begin
    if RUN_HOLD_CYC_OVR >= 0 then
      return RUN_HOLD_CYC_OVR;
    else
      return (3 * CLK_HZ) / 2;          -- ~1.5 s at the configured CLK_HZ
    end if;
  end function;
  constant RUN_HOLD_CYC : integer := run_hold_cycles;
  signal run_hold_cnt  : integer range 0 to RUN_HOLD_CYC := RUN_HOLD_CYC;
  signal run_hold      : std_logic;     -- '1' while the RUNNING window is held

  ----------------------------------------------------------------------------
  -- Expected bit at index i, with the TEST-ONLY corruption applied at
  -- CORRUPT_IDX (default -1 => never corrupts => returns the true golden bit).
  ----------------------------------------------------------------------------
  function exp_bit(i : integer) return std_logic is
  begin
    if i = CORRUPT_IDX then
      return not GV_C(i);
    else
      return GV_C(i);
    end if;
  end function;

begin

  ----------------------------------------------------------------------------
  -- PS clocking: instantiate the minimal Zynq MPSoC BD wrapper. The BD itself
  -- is created by the TCL build script's kr260_create_clocking_bd proc; the
  -- VHDL wrapper Vivado generates from `make_wrapper -import` matches this
  -- component declaration (entity name kr260_clocking_wrapper, two output
  -- ports pl_clk0 + pl_resetn0).
  --
  -- For GHDL sim of this wrapper we would need a behavioural stub of
  -- kr260_clocking_wrapper that drives pl_clk0 with a 10 ns period and
  -- pl_resetn0 from '0' -> '1' after a few cycles (task 3.3 -- not in this
  -- stage's scope).
  ----------------------------------------------------------------------------
  u_clocking : kr260_clocking_wrapper
    port map (
      pl_clk0    => clk,
      pl_resetn0 => pl_resetn
    );

  rst_async <= not pl_resetn;

  ----------------------------------------------------------------------------
  -- Iterative turbo decoder core, instantiated UNMODIFIED. Generic overrides:
  -- K_MAX => 512, MAX_ITERATIONS => GV_MAX_ITER (2), all three recurrence-
  -- pipelining levers ON. Decoded bits are bit-identical to the DE2 25 MHz
  -- build and the GHDL/cocotb golden lane.
  ----------------------------------------------------------------------------
  u_core : turbo_decoder_top
    generic map (
      K_MAX          => K_MAX,
      MAX_ITERATIONS => MAX_ITERATIONS,
      ANCHOR_NORM    => true,
      BAL_TREE_FOLD  => true,
      PIPE_DFOLD     => true
    )
    port map (
      clk       => clk,
      rst       => core_rst,
      in_start  => core_start,
      k_in      => std_logic_vector(to_unsigned(GV_K, W_K)),
      da_valid  => core_dav,
      da1_in    => core_da1,
      da2_in    => core_da2,
      da3_in    => core_da3,
      out_valid => core_ov,
      out_last  => core_ol,
      c_out     => core_cout,
      busy      => core_busy,
      done      => core_done
    );

  ----------------------------------------------------------------------------
  -- Reset deassertion -> single-cycle `restart` pulse on `clk`. The PS
  -- pl_resetn0 already comes out of proc_sys_reset (synchronized to pl_clk0),
  -- but we re-synchronize through one more stage and edge-detect the rising
  -- edge (assertion -> deassertion) to produce the single-cycle restart -- a
  -- direct analog of the DE2 wrapper's KEY0 falling-edge detect.
  ----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      pl_resetn_q <= pl_resetn_q(0) & pl_resetn;
      pl_resetn_d <= pl_resetn_q(1);
    end if;
  end process;
  restart <= '1' when (pl_resetn_d = '0' and pl_resetn_q(1) = '1') else '0';

  ----------------------------------------------------------------------------
  -- Self-check FSM (ported VERBATIM from the DE2 wrapper). Resets the core,
  -- pulses in_start with k_in=GV_K, streams the GV_N_COLS d_a columns one per
  -- cycle on da_valid, then captures out_valid c_out bits and compares them
  -- to GV_C (with the optional CORRUPT_IDX fault). Verdict latches at end-of-
  -- stream: PASS iff err_cnt = 0 AND frame_err = '0', else FAIL.
  ----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      -- defaults each cycle
      core_start <= '0';
      core_dav   <= '0';

      if restart = '1' then
        chk       <= CH_RESET;
        core_rst  <= '1';
        load_idx  <= 0;
        cmp_idx   <= 0;
        pass_f    <= '0';
        fail_f    <= '0';
        done_f    <= '0';
        err_cnt   <= (others => '0');
        frame_err <= '0';
      else
        case chk is
          when CH_RESET =>
            core_rst  <= '1';
            load_idx  <= 0;
            cmp_idx   <= 0;
            pass_f    <= '0';
            fail_f    <= '0';
            done_f    <= '0';
            err_cnt   <= (others => '0');
            frame_err <= '0';
            chk       <= CH_START;

          when CH_START =>
            core_rst   <= '0';
            core_start <= '1';
            chk        <= CH_LOAD;

          when CH_LOAD =>
            core_rst <= '0';
            core_dav <= '1';
            core_da1 <= std_logic_vector(to_signed(GV_DA1(load_idx), W_EXT));
            core_da2 <= std_logic_vector(to_signed(GV_DA2(load_idx), W_EXT));
            core_da3 <= std_logic_vector(to_signed(GV_DA3(load_idx), W_EXT));
            if load_idx = GV_N_COLS - 1 then
              load_idx <= 0;
              chk      <= CH_RUN;
            else
              load_idx <= load_idx + 1;
            end if;

          when CH_RUN =>
            core_rst <= '0';
            if core_ov = '1' then
              if cmp_idx < GV_K then
                if core_cout /= exp_bit(cmp_idx) then
                  if err_cnt < to_unsigned(ERR_MAX, ERR_W) then
                    err_cnt <= err_cnt + 1;
                  end if;
                end if;

                if cmp_idx = GV_K - 1 then
                  if core_ol /= '1' then
                    frame_err <= '1';
                  end if;
                  if (core_cout = exp_bit(cmp_idx)) and (err_cnt = 0)
                     and (core_ol = '1') then
                    pass_f <= '1';
                    done_f <= '1';
                    chk    <= CH_PASS;
                  else
                    fail_f <= '1';
                    done_f <= '1';
                    chk    <= CH_FAIL;
                  end if;
                  cmp_idx <= cmp_idx + 1;
                else
                  if core_ol = '1' then
                    frame_err <= '1';
                  end if;
                  cmp_idx <= cmp_idx + 1;
                end if;
              else
                frame_err <= '1';
                fail_f    <= '1';
                done_f    <= '1';
                chk       <= CH_FAIL;
              end if;
            end if;

          when CH_PASS =>
            core_rst <= '0';
            pass_f   <= '1';
            done_f   <= '1';

          when CH_FAIL =>
            core_rst <= '0';
            fail_f   <= '1';
            done_f   <= '1';
        end case;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Free-running heartbeat counter -- LED-0 blink phase. Bit 25 toggles every
  -- ~0.336 s at 100 MHz -- matches the DE2's visual heartbeat rate.
  ----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      hb_cnt <= hb_cnt + 1;
    end if;
  end process;
  hb <= hb_cnt(25);

  ----------------------------------------------------------------------------
  -- Minimum RUNNING-display window. Reloaded on each restart, then counts
  -- down to 0 free-running. While nonzero, LED-0 stays in BLINK mode even
  -- after the verdict latches, so a human can see the running pulse before
  -- the solid PASS.
  ----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if restart = '1' then
        run_hold_cnt <= RUN_HOLD_CYC;
      elsif run_hold_cnt /= 0 then
        run_hold_cnt <= run_hold_cnt - 1;
      end if;
    end if;
  end process;
  run_hold <= '1' when run_hold_cnt /= 0 else '0';

  ----------------------------------------------------------------------------
  -- Two-LED status encoding.
  --   LEDS(0) "alive / well":
  --     blink while running (run_hold active OR no verdict yet),
  --     solid '1' after PASS, '0' after FAIL.
  --   LEDS(1) "fail": solid '1' only on FAIL, '0' otherwise.
  -- Combinational decode -- the FSM/heartbeat registers feed it directly so
  -- there is no extra register stage in the LED path.
  ----------------------------------------------------------------------------
  -- LED-0: while running OR within the post-verdict hold window, blink at hb;
  -- once the hold expires AND PASS latched, solid; on FAIL, off.
  LEDS(0) <= hb     when (run_hold = '1' or done_f = '0') else
             '1'    when (pass_f = '1') else
             '0';
  -- LED-1: PASS / running -> off; FAIL (after the hold expires) -> on. We
  -- gate the FAIL display on the same run_hold so the two LEDs don't both
  -- come on briefly during the held-RUNNING window (which is the DE2 wrapper
  -- behaviour for its LCD verdict line too).
  LEDS(1) <= '1' when (fail_f = '1' and run_hold = '0') else '0';

end architecture rtl;
