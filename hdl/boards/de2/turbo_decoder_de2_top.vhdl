library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.turbo_decoder_golden_pkg.all;  -- GV_* on-chip golden vector (K=512)

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
entity turbo_decoder_de2_top is
  generic (
    -- TEST-ONLY fault-injection knob. Default -1 disables it, so the
    -- synthesized board behaviour is the real golden compare. The GHDL
    -- self-check TB sets it to a valid index (0..GV_K-1) to corrupt one
    -- expected bit and prove the comparator actually reaches FAIL. Synthesis
    -- uses the default.
    CORRUPT_IDX : integer := -1
  );
  port (
    CLOCK_50 : in  std_logic;
    KEY      : in  std_logic_vector(3 downto 0);   -- active-low; KEY[0] restart
    LEDR     : out std_logic_vector(1 downto 0);   -- LEDR[0]=FAIL, LEDR[1]=DONE
    LEDG     : out std_logic_vector(1 downto 0);   -- LEDG[0]=PASS, LEDG[1]=RUN
    HEX0     : out std_logic_vector(6 downto 0);
    HEX1     : out std_logic_vector(6 downto 0)
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
        chk      <= CH_RESET;
        core_rst <= '1';
        load_idx <= 0;
        cmp_idx  <= 0;
        pass_f   <= '0';
        fail_f   <= '0';
        done_f   <= '0';
      else
        case chk is
          when CH_RESET =>
            core_rst <= '1';        -- one full cycle of reset to the core
            load_idx <= 0;
            cmp_idx  <= 0;
            pass_f   <= '0';
            fail_f   <= '0';
            done_f   <= '0';
            chk      <= CH_START;

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
            if core_ov = '1' then
              if cmp_idx < GV_K then
                if core_cout /= exp_bit(cmp_idx) then
                  -- bit mismatch
                  fail_f <= '1';
                  done_f <= '1';
                  chk    <= CH_FAIL;
                elsif cmp_idx = GV_K - 1 then
                  -- last expected bit: it must coincide with out_last.
                  if core_ol = '1' then
                    pass_f <= '1';
                    done_f <= '1';
                    chk    <= CH_PASS;
                  else
                    fail_f <= '1';   -- ran long: no out_last at K-1
                    done_f <= '1';
                    chk    <= CH_FAIL;
                  end if;
                  cmp_idx <= cmp_idx + 1;
                else
                  -- matched, not last yet: out_last arriving early is a failure.
                  if core_ol = '1' then
                    fail_f <= '1';   -- short: out_last before K-1
                    done_f <= '1';
                    chk    <= CH_FAIL;
                  end if;
                  cmp_idx <= cmp_idx + 1;
                end if;
              else
                -- more output than K bits expected -> failure.
                fail_f <= '1';
                done_f <= '1';
                chk    <= CH_FAIL;
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
end architecture rtl;
