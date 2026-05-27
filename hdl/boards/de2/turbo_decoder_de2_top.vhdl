library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.turbo_decoder_golden_pkg.all;  -- GV_* on-chip golden vector (K=512)
use work.lcd_format_pkg.all;            -- uint_to_ascii (shared LCD helper)

-- Altera DE2 (Cyclone II EP2C35F672C6) board demo for the iterative turbo
-- decoder core turbo_decoder_top. The core is instantiated UNMODIFIED (only the
-- generic overrides K_MAX => 512 -> N_MAX = 515 internally, and
-- MAX_ITERATIONS => GV_MAX_ITER = 2 to match the golden row's max_iter); this
-- wrapper adds only board-adaptation logic:
--
--   * a PLL deriving a ~12.5 MHz functional clock from the 50 MHz CLOCK_50
--     (CLOCK_50 / 4 via altpll in synthesis; a behavioural /4 divider in GHDL).
--     The whole demo (the decoder core + self-check FSM) runs on this derived
--     clock. The decoder's pre-existing ~64.8 ns forward alpha-recurrence cone
--     caps Fmax at 15.43 MHz, so a slower clock (80 ns period) is required
--     (Option A); 50 MHz would need algorithmic recurrence pipelining.
--   * an on-chip golden-vector ROM (turbo_decoder_golden_pkg) holding the
--     K=512, max_iter=2 row of hdl/vectors/turbo_decoder_top.csv: the 3x(K+4)
--     channel-LLR matrix d_a (W_EXT=12 signed codes, column-major) and the 512
--     expected hard-decision decoded bits c;
--   * a self-check FSM that resets the core, pulses in_start with k_in=512,
--     streams the 516 d_a column beats on da_valid, waits out the multi-thousand
--     cycle whole-block decode, captures every out_valid c_out bit, compares it
--     to the expected c bit at the same index, checks out_last arrives exactly
--     at bit K-1, and latches a sticky pass / fail; and
--   * pass/fail/running indication on LEDs and a status code on the 7-seg
--     displays via the shared hdl/boards/hex7seg.vhdl.
--
-- Fully self-contained: after power-up (or a KEY[0] press to re-run) the demo
-- runs to a verdict with no human input. Driven by the PLL-derived clock.
--
-- I/O / verdict mapping (identical to the TX demo):
--   CLOCK_50         50 MHz board clock (PLL reference; feeds the PLL only)
--   KEY[0]           active-low push button: press = synchronous restart
--   LEDG[0]          PASS  (lit when the self-check passed)
--   LEDR[0]          FAIL  (lit when the self-check failed / mismatched)
--   LEDG[1]          RUNNING / not-yet-done (lit while the check is in flight)
--   LEDR[1]          DONE   (lit once a verdict has been reached)
--   HEX0/HEX1        status code via two hex7seg nibble decoders:
--                      pass    -> HEX1=0xA HEX0=0x5  ("A5")
--                      fail    -> HEX1=0xF HEX0=0xF  ("FF")
--                      running -> HEX1=0x0 HEX0=0x0  ("00")
--   LCD_*            16x2 HD44780 character LCD (ADDITIVE; the 7-seg/LEDs are
--                    unchanged). Line 1 = fixed demo label "3GPP TURBO K=512";
--                    line 2 = live status with an ALWAYS-ON blink heartbeat:
--                    "RUNNING" is HELD for a minimum ~1.5 s display window
--                    (sized from CLK_HZ) after each KEY0 start -- the decode
--                    actually finishes in <1 ms, so without this hold the
--                    RUNNING state would flash by invisibly -- then it switches
--                    to the latched "PASS"/"FAIL". A heartbeat char ('*')
--                    blinks (~0.34 s) in EVERY state (e.g. "PASS *"/"PASS") so
--                    the board always shows a visible alive pulse. The verdict
--                    itself still latches in <1 ms (LEDs/7-seg unchanged); only
--                    the LCD's RUNNING *display* is held longer. Driven by the
--                    shared hdl/boards/hd44780_lcd.vhdl with CLK_HZ=>12_500_000.
entity turbo_decoder_de2_top is
  generic (
    -- TEST-ONLY fault-injection knob. Default -1 disables it, so the
    -- synthesized board behaviour is the real golden compare. The GHDL
    -- self-check TB sets it to a valid index (0..GV_K-1) to corrupt one
    -- expected bit and prove the comparator actually reaches FAIL. Synthesis
    -- uses the default.
    CORRUPT_IDX : integer := -1;
    -- TEST-ONLY override for the minimum RUNNING-display hold (in cycles).
    -- Default -1 keeps the real ~1.5 s board window; the GHDL byte-sequence TB
    -- sets it small so the latched verdict line ("PASS e=000 it=2*" /
    -- "FAIL e=NNN it=2*") reaches the LCD within the sim budget. Synthesis uses
    -- the default => board behaviour byte-identical.
    RUN_HOLD_CYC_OVR : integer := -1
  );
  port (
    CLOCK_50 : in  std_logic;
    KEY      : in  std_logic_vector(3 downto 0);   -- active-low; KEY[0] restart
    LEDR     : out std_logic_vector(1 downto 0);   -- LEDR[0]=FAIL, LEDR[1]=DONE
    LEDG     : out std_logic_vector(1 downto 0);   -- LEDG[0]=PASS, LEDG[1]=RUN
    HEX0     : out std_logic_vector(6 downto 0);
    HEX1     : out std_logic_vector(6 downto 0);
    -- 16x2 HD44780 character LCD bus (additive status display).
    LCD_DATA : out std_logic_vector(7 downto 0);   -- DB7..DB0
    LCD_RW   : out std_logic;                       -- tied 0 (write-only)
    LCD_EN   : out std_logic;                       -- E strobe
    LCD_RS   : out std_logic;                       -- 0=command, 1=data
    LCD_ON   : out std_logic;                       -- panel power (driven '1')
    LCD_BLON : out std_logic                        -- backlight (driven '1')
  );
end entity turbo_decoder_de2_top;

architecture rtl of turbo_decoder_de2_top is

  -- Core sizing for the K=512 board demo. The core defaults to the LTE maxima
  -- (K_MAX=6144 -> N_MAX=6147), which would not fit / would over-allocate the
  -- M4K stores; the demo overrides K_MAX=512 (-> N_MAX=515 inside the core).
  constant DEMO_K_MAX : integer := 512;
  -- W_EXT is the core's stored exchange word width; the golden d_a codes are
  -- W_EXT signed (Q7.4). Keep the core default by referencing it explicitly.
  constant W_EXT : integer := 12;
  constant W_K   : integer := 13;

  component pll_12p5 is
    port (
      areset : in  std_logic := '0';
      inclk0 : in  std_logic;
      c0     : out std_logic;
      locked : out std_logic
    );
  end component;

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
      MAX_ITERATIONS : integer := 8
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

  component hex7seg is
    port (
      nibble_i : in  std_logic_vector(3 downto 0);
      seg_o    : out std_logic_vector(6 downto 0)
    );
  end component;

  -- Shared HD44780 16x2 LCD controller (board component; CLK_HZ scales delays).
  component hd44780_lcd is
    generic (
      CLK_HZ : integer := 50_000_000
    );
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      line1_i  : in  string(1 to 16);
      line2_i  : in  string(1 to 16);
      lcd_data : out std_logic_vector(7 downto 0);
      lcd_rs   : out std_logic;
      lcd_rw   : out std_logic;
      lcd_en   : out std_logic;
      lcd_on   : out std_logic;
      lcd_blon : out std_logic
    );
  end component;

  -- PLL-derived functional clock for the whole demo.
  signal clk      : std_logic;
  signal pll_lock : std_logic;

  -- Self-check FSM states.
  --   CH_RESET  : hold core in reset one cycle
  --   CH_START  : present k_in=512, pulse in_start (core S_IDLE -> S_LOAD_D)
  --   CH_LOAD   : stream the GV_N_COLS d_a column beats with da_valid
  --   CH_RUN    : wait the decode out; capture out_valid c_out, compare to GV_C
  --   CH_PASS   : sticky pass
  --   CH_FAIL   : sticky fail
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

  -- KEY[0] active-low restart, synchronized + edge-detected.
  signal key0_sync : std_logic_vector(1 downto 0) := (others => '1');
  signal key0_prev : std_logic := '1';
  signal restart   : std_logic;

  -- 7-seg status nibbles.
  signal hex0_nib : std_logic_vector(3 downto 0);
  signal hex1_nib : std_logic_vector(3 downto 0);

  -- Status flags driven from the FSM.
  signal pass_f : std_logic := '0';
  signal fail_f : std_logic := '0';
  signal done_f : std_logic := '0';

  -- Output-bit error count (the primary LCD stat). The CH_RUN comparator now
  -- COUNTS mismatches across the whole decoded-bit stream instead of bailing on
  -- the first one; the verdict latches at end-of-stream (PASS iff err_cnt = 0
  -- AND framing correct). ERR_W = 10 bits holds the 3-digit display max (999)
  -- with margin; the count saturates at ERR_MAX. Real counts are bounded by
  -- GV_K = 512.
  constant ERR_W   : integer := 10;
  constant ERR_MAX : integer := 999;
  signal err_cnt   : unsigned(ERR_W-1 downto 0) := (others => '0');
  -- Framing-error flag: set if out_last lands early/late/missing or the stream
  -- over-runs K bits. PASS requires err_cnt = 0 AND frame_err = '0'.
  signal frame_err : std_logic := '0';

  -- Free-running heartbeat counter for the LCD liveness glyph. At 12.5 MHz,
  -- bit 22 toggles every 2^22 / 12.5e6 ~ 0.34 s -> a clearly visible blink.
  -- The heartbeat is ALWAYS-ON: it blinks in every display state (PASS, FAIL,
  -- and RUNNING) so the board always shows a visible "alive" pulse.
  signal hb_cnt : unsigned(23 downto 0) := (others => '0');
  signal hb     : std_logic;            -- current heartbeat phase (' '/'*')

  -- Minimum RUNNING-display window. The self-check latches its verdict in
  -- well under 1 ms (K=512, H=4, 12.5 MHz), so the RUNNING state would flash
  -- by invisibly. This counter, sized for ~1.5 s from CLK_HZ and (re)loaded on
  -- each KEY0 restart, holds the LCD's RUNNING *display* for at least that long
  -- before the real PASS/FAIL verdict is shown. It only gates the LCD string;
  -- the verdict/LED/7-seg path (pass_f/fail_f/done_f) is UNCHANGED.
  constant CLK_HZ      : integer := 12_500_000;
  -- ~1.5 s on the board; a TB may override small (RUN_HOLD_CYC_OVR >= 0) so
  -- the verdict line reaches the LCD within the sim budget. Default keeps 1.5 s.
  function run_hold_cycles return integer is
  begin
    if RUN_HOLD_CYC_OVR >= 0 then
      return RUN_HOLD_CYC_OVR;
    else
      return (3 * CLK_HZ) / 2;
    end if;
  end function;
  constant RUN_HOLD_CYC : integer := run_hold_cycles;
  signal run_hold_cnt  : integer range 0 to RUN_HOLD_CYC := RUN_HOLD_CYC;
  signal run_hold      : std_logic;     -- '1' while the RUNNING window is held

  -- LCD line buffers (combinational): line 1 fixed label, line 2 live status.
  constant LCD_LABEL : string(1 to 16) := "3GPP TURBO K=512";
  signal lcd_line2   : string(1 to 16);
  -- Heartbeat glyph as a 1-char string for line-2 splicing.
  signal hb_chr      : string(1 to 1);
  -- Rendered 3-digit error count (e.g. "000", "042"), shared helper.
  signal err_str     : string(1 to 3);
  -- Static configured max-iterations field, rendered as a single ASCII digit
  -- from the GV_MAX_ITER constant (NOT a dynamic count). One digit suffices
  -- for the configured value (2); if a future config needs >1 digit the it=
  -- field is dropped first (error count is the primary stat).
  constant IT_STR : string(1 to 1) :=
    uint_to_ascii(to_unsigned(GV_MAX_ITER, 4), 1);

  -- Expected bit at index i, with the TEST-ONLY corruption applied at
  -- CORRUPT_IDX (default -1 => never corrupts => returns the true golden bit).
  function exp_bit(i : integer) return std_logic is
  begin
    if i = CORRUPT_IDX then
      return not GV_C(i);
    else
      return GV_C(i);
    end if;
  end function;
begin
  ---------------------------------------------------------------------------
  -- PLL: derive the ~12.5 MHz functional clock from CLOCK_50 (CLOCK_50 / 4).
  ---------------------------------------------------------------------------
  u_pll : pll_12p5
    port map (
      areset => '0',
      inclk0 => CLOCK_50,
      c0     => clk,
      locked => pll_lock
    );

  ---------------------------------------------------------------------------
  -- Iterative turbo decoder core, instantiated UNMODIFIED (generic overrides
  -- K_MAX => 512 and MAX_ITERATIONS => GV_MAX_ITER only).
  ---------------------------------------------------------------------------
  u_core : turbo_decoder_top
    generic map (
      K_MAX          => DEMO_K_MAX,
      MAX_ITERATIONS => GV_MAX_ITER
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

  ---------------------------------------------------------------------------
  -- KEY[0] synchronize + falling-edge (press) detect -> single-cycle restart.
  ---------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      key0_sync <= key0_sync(0) & KEY(0);
      key0_prev <= key0_sync(1);
    end if;
  end process;
  -- press = transition from released ('1') to pressed ('0').
  restart <= '1' when (key0_prev = '1' and key0_sync(1) = '0') else '0';

  ---------------------------------------------------------------------------
  -- Self-check FSM.
  ---------------------------------------------------------------------------
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
            core_rst  <= '1';       -- one full cycle of reset to the core
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
            core_start <= '1';      -- pulse in_start (core S_IDLE -> S_LOAD_D)
            chk        <= CH_LOAD;

          when CH_LOAD =>
            core_rst <= '0';
            -- Stream the GV_N_COLS d_a columns, one per cycle, on da_valid.
            -- in_start was dropped (default) this edge; the core advanced to
            -- S_LOAD_D and consumes da_valid beats from index 0.
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
            -- Wait out the whole-block iterative decode (thousands of cycles
            -- between the last load beat and the first out_valid), then
            -- capture/compare each c_out bit.
            -- COUNT mismatches across the whole decoded-bit stream (do NOT bail
            -- on the first one); accumulate into the saturating err_cnt. Framing
            -- problems set frame_err. The verdict latches at end-of-stream:
            -- PASS iff err_cnt = 0 AND frame_err = '0', else FAIL. Verdict
            -- MEANING is identical to the bail-on-first FSM.
            if core_ov = '1' then
              if cmp_idx < GV_K then
                -- per-bit compare: increment err_cnt (saturating) on mismatch,
                -- but keep streaming so the full count accumulates.
                if core_cout /= exp_bit(cmp_idx) then
                  if err_cnt < to_unsigned(ERR_MAX, ERR_W) then
                    err_cnt <= err_cnt + 1;
                  end if;
                end if;

                if cmp_idx = GV_K - 1 then
                  -- last expected bit: out_last MUST coincide with it.
                  if core_ol /= '1' then
                    frame_err <= '1';   -- ran long: no out_last at K-1
                  end if;
                  -- end of stream -> latch the verdict from accumulated state.
                  -- The final bit's mismatch is reflected by re-testing the
                  -- current bit here (the registered err_cnt updates next edge).
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
                  -- mid-stream: out_last arriving early is a framing error, but
                  -- still keep counting / advancing to the end of the stream.
                  if core_ol = '1' then
                    frame_err <= '1';   -- short: out_last before K-1
                  end if;
                  cmp_idx <= cmp_idx + 1;
                end if;
              else
                -- more output than K bits expected -> framing error; latch FAIL.
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

  ---------------------------------------------------------------------------
  -- LED indication.
  ---------------------------------------------------------------------------
  LEDG(0) <= pass_f;                 -- PASS
  LEDR(0) <= fail_f;                 -- FAIL
  LEDG(1) <= not done_f;             -- RUNNING (lit until a verdict)
  LEDR(1) <= done_f;                 -- DONE

  ---------------------------------------------------------------------------
  -- 7-seg status: pass="A5", fail="FF", running="00".
  ---------------------------------------------------------------------------
  hex0_nib <= x"5" when pass_f = '1' else
              x"F" when fail_f = '1' else
              x"0";
  hex1_nib <= x"A" when pass_f = '1' else
              x"F" when fail_f = '1' else
              x"0";

  u_hex0 : hex7seg port map (nibble_i => hex0_nib, seg_o => HEX0);
  u_hex1 : hex7seg port map (nibble_i => hex1_nib, seg_o => HEX1);

  ---------------------------------------------------------------------------
  -- LCD status display (ADDITIVE). The verdict path above is unchanged: this
  -- only READS pass_f/fail_f/done_f. Line 1 is the fixed demo label; line 2 is
  -- decoded combinationally from the same flags, with an always-on blink
  -- heartbeat and a minimum RUNNING-display window so a human can actually see
  -- the running state (it otherwise resolves in well under 1 ms).
  ---------------------------------------------------------------------------
  -- Free-running heartbeat counter (functional clock). hb_cnt(23) (~0.34 s)
  -- is the blink phase, used in EVERY display state.
  process (clk)
  begin
    if rising_edge(clk) then
      hb_cnt <= hb_cnt + 1;
    end if;
  end process;
  hb <= hb_cnt(23);

  -- Minimum RUNNING-display window (~1.5 s). Reloaded on a KEY0 restart, then
  -- counts down to 0 free-running. While nonzero, the LCD HOLDS the RUNNING
  -- string regardless of the (already-latched) verdict. The verdict flags
  -- themselves are untouched — only the displayed line-2 string is gated.
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

  -- Line 2: hold RUNNING for the minimum display window, then show the latched
  -- verdict with the rendered error count + the STATIC configured iteration
  -- field; the heartbeat ('*'/' ') is always-on in column 16. Each branch is
  -- exactly 16 chars:
  --   "PASS e=000 it=2*"  ("PASS e="=7 + NNN=3 + " it="=4 + N=1 + hb=1)
  --   "FAIL e=NNN it=2*"
  --   "RUNNING        *"  (count not meaningful until the verdict latches)
  -- The error count is spliced via uint_to_ascii(err_cnt, 3); the it= digit is
  -- the static GV_MAX_ITER constant (IT_STR), documented as configured-max, not
  -- a measured dynamic count.
  hb_chr  <= "*" when hb = '1' else " ";
  err_str <= uint_to_ascii(err_cnt, 3);

  lcd_line2 <=
    -- still within the minimum RUNNING-display window: show RUNNING
    "RUNNING        " & hb_chr                            when (run_hold = '1') else
    -- verdict shown once the RUNNING window has elapsed
    "PASS e=" & err_str & " it=" & IT_STR & hb_chr        when (pass_f = '1')   else
    "FAIL e=" & err_str & " it=" & IT_STR & hb_chr        when (fail_f = '1')   else
    -- not done yet and window elapsed (e.g. a genuinely long/hung run)
    "RUNNING        " & hb_chr;

  u_lcd : hd44780_lcd
    generic map (
      CLK_HZ => 12_500_000          -- the decoder demo's PLL-derived clock
    )
    port map (
      clk      => clk,
      rst      => restart,           -- KEY0 restart re-runs the init
      line1_i  => LCD_LABEL,
      line2_i  => lcd_line2,
      lcd_data => LCD_DATA,
      lcd_rs   => LCD_RS,
      lcd_rw   => LCD_RW,
      lcd_en   => LCD_EN,
      lcd_on   => LCD_ON,
      lcd_blon => LCD_BLON
    );
end architecture rtl;
