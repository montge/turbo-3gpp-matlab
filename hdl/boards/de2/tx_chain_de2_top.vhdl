library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;          -- QPP_W
use work.tx_chain_golden_pkg.all;  -- GV_* on-chip golden vector (K=40 row)

-- Altera DE2 (Cyclone II EP2C35F672C6) board demo for the synthesis-hardened
-- tx_chain_top core. The core is instantiated UNMODIFIED; this wrapper adds
-- only board-adaptation logic:
--
--   * an on-chip golden-vector ROM (tx_chain_golden_pkg) holding the K=40 row
--     of hdl/vectors/tx_chain.csv: K/params, the 40 input bits c, the 400
--     expected output bits e;
--   * a self-check FSM that resets the core, pulses in_start with K/params,
--     streams c into the core, captures every out_valid e_bit, compares it to
--     the expected e bit at the same index, checks that `last` arrives exactly
--     at bit E-1, and latches a sticky pass / fail; and
--   * pass/fail/running indication on LEDs and a status code on the 7-seg
--     displays via the shared hdl/boards/hex7seg.vhdl.
--
-- Fully self-contained: after power-up (or a KEY[0] press to re-run) the demo
-- runs to a verdict with no human input. Driven by the real 50 MHz CLOCK_50.
--
-- I/O / verdict mapping:
--   CLOCK_50         50 MHz board clock (functional clock for the whole demo)
--   KEY[0]           active-low push button: press = synchronous restart
--   LEDG[0]          PASS  (lit when the self-check passed)
--   LEDR[0]          FAIL  (lit when the self-check failed / mismatched)
--   LEDG[1]          RUNNING / not-yet-done (lit while the check is in flight)
--   LEDR[1]          DONE   (lit once a verdict has been reached)
--   HEX0             status code: 'P' (pass-like 'P'->we use the digit set,
--                    see below), 'F' fail, '-' running  (low nibble code)
--   HEX1             high nibble of the FSM state code (progress)
-- The 7-seg uses the shared hex7seg nibble decoder, so the status is shown as
-- a hex digit: HEX0 = 0x5 ('S'-ish) is unused; we map:
--   running -> HEX0 shows 0x0 ("-" style not available, so blank via 0xF off),
--   pass    -> HEX0 shows 0xA, HEX1 shows 0x5 (=> "A5" = "pAss" signature),
--   fail    -> HEX0 shows 0xF, HEX1 shows 0xF (=> "FF").
-- (hex7seg is a pure nibble->seg decoder; richer glyphs would need a new
-- decoder, which is out of scope — status nibble codes are sufficient.)
entity tx_chain_de2_top is
  generic (
    -- TEST-ONLY fault-injection knob. Default -1 disables it, so the
    -- synthesized board behaviour is the real golden compare. The GHDL
    -- self-check TB sets it to a valid index to corrupt one expected bit and
    -- prove the comparator actually reaches FAIL. Synthesis uses the default.
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
end entity tx_chain_de2_top;

architecture rtl of tx_chain_de2_top is
  component tx_chain_top is
    generic (
      MAXK   : integer := 6144;
      DMAX   : integer := 6148;
      KW_MAX : integer := 3 * 6176
    );
    port (
      clk        : in  std_logic;
      rst        : in  std_logic;
      in_start   : in  std_logic;
      k_in       : in  std_logic_vector(QPP_W-1 downto 0);
      n_ref_in   : in  std_logic_vector(15 downto 0);
      i_lbrm     : in  std_logic;
      rv_in      : in  std_logic_vector(1 downto 0);
      e_in       : in  std_logic_vector(15 downto 0);
      c_in       : in  std_logic;
      c_in_valid : in  std_logic;
      out_valid  : out std_logic;
      e_bit      : out std_logic;
      last       : out std_logic
    );
  end component;

  component hex7seg is
    port (
      nibble_i : in  std_logic_vector(3 downto 0);
      seg_o    : out std_logic_vector(6 downto 0)
    );
  end component;

  ---------------------------------------------------------------------------
  -- Demo buffer-depth overrides, sized for the K=40 golden vector. The
  -- hardened cores default these generics to the TS36.212 maxima (MAXK=6144,
  -- DMAX=6148, KW_MAX=18528), which for the EP2C35 inferred ~85k logic cells
  -- (2.5x over the 33,216 available) because the buffers became flip-flops.
  -- For the K=40 demo the required depths are tiny, so we override small:
  --
  --   K   = GV_K  = 40                      (code-block length)
  --   D   = K + 4 = 44                      (turbo_encode_top output cols feed
  --                                          rate_matching_top as D)
  --   K_Pi = 32*ceil(D/32) = 32*ceil(44/32) = 32*2 = 64   (sub-block padded)
  --   K_w  = 3*K_Pi = 192                   (circular-buffer w depth; the max
  --                                          write index is K_Pi+2*(K_Pi-1)+1
  --                                          = 3*K_Pi-1 = 191)
  --
  -- Round each up to a safe margin (still ~100x smaller than the 6144 maxima):
  --   DEMO_MAXK   = 64  (>= 40)
  --   DEMO_DMAX   = 64  (>= 44)
  --   DEMO_KW_MAX = 256 (>= 192)
  ---------------------------------------------------------------------------
  constant DEMO_MAXK   : integer := 64;
  constant DEMO_DMAX   : integer := 64;
  constant DEMO_KW_MAX : integer := 256;

  -- Self-check FSM states.
  --   CH_RESET  : hold core in reset one cycle
  --   CH_START  : present K/params, pulse in_start (core S_IDLE->S_START)
  --   CH_ARM    : drop in_start (core S_START->S_RUN)
  --   CH_LOAD   : stream the GV_K c bits with c_in_valid
  --   CH_RUN    : capture out_valid e bits, compare to expected
  --   CH_PASS   : sticky pass
  --   CH_FAIL   : sticky fail
  type chk_state_t is (CH_RESET, CH_START, CH_ARM, CH_LOAD, CH_RUN,
                       CH_PASS, CH_FAIL);
  signal chk : chk_state_t := CH_RESET;

  -- Core interface signals.
  signal core_rst    : std_logic := '1';
  signal core_start  : std_logic := '0';
  signal core_cin    : std_logic := '0';
  signal core_cinv   : std_logic := '0';
  signal core_ov     : std_logic;
  signal core_eb     : std_logic;
  signal core_last   : std_logic;

  signal load_idx : integer range 0 to GV_K := 0;   -- next c bit to stream
  signal cmp_idx  : integer range 0 to GV_E := 0;    -- next expected e bit

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
      return not GV_E_BITS(i);
    else
      return GV_E_BITS(i);
    end if;
  end function;
begin
  ---------------------------------------------------------------------------
  -- Hardened TX-chain core, instantiated UNMODIFIED.
  ---------------------------------------------------------------------------
  u_core : tx_chain_top
    generic map (
      MAXK   => DEMO_MAXK,
      DMAX   => DEMO_DMAX,
      KW_MAX => DEMO_KW_MAX
    )
    port map (
      clk        => CLOCK_50,
      rst        => core_rst,
      in_start   => core_start,
      k_in       => std_logic_vector(to_unsigned(GV_K, QPP_W)),
      n_ref_in   => std_logic_vector(to_unsigned(GV_N_REF, 16)),
      i_lbrm     => GV_I_LBRM,
      rv_in      => std_logic_vector(to_unsigned(GV_RV, 2)),
      e_in       => std_logic_vector(to_unsigned(GV_E, 16)),
      c_in       => core_cin,
      c_in_valid => core_cinv,
      out_valid  => core_ov,
      e_bit      => core_eb,
      last       => core_last
    );

  ---------------------------------------------------------------------------
  -- KEY[0] synchronize + falling-edge (press) detect -> single-cycle restart.
  ---------------------------------------------------------------------------
  process (CLOCK_50)
  begin
    if rising_edge(CLOCK_50) then
      key0_sync <= key0_sync(0) & KEY(0);
      key0_prev <= key0_sync(1);
    end if;
  end process;
  -- press = transition from released ('1') to pressed ('0').
  restart <= '1' when (key0_prev = '1' and key0_sync(1) = '0') else '0';

  ---------------------------------------------------------------------------
  -- Self-check FSM.
  ---------------------------------------------------------------------------
  process (CLOCK_50)
  begin
    if rising_edge(CLOCK_50) then
      -- defaults each cycle
      core_start <= '0';
      core_cinv  <= '0';
      core_cin   <= '0';

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
            core_start <= '1';      -- pulse in_start (core S_IDLE -> S_START)
            chk        <= CH_ARM;

          when CH_ARM =>
            core_rst   <= '0';
            -- in_start dropped (default); core S_START -> S_RUN this edge.
            chk        <= CH_LOAD;

          when CH_LOAD =>
            core_rst <= '0';
            -- Stream the GV_K input bits, one per cycle.
            core_cin  <= GV_C(load_idx);
            core_cinv <= '1';
            if load_idx = GV_K - 1 then
              load_idx <= 0;
              chk      <= CH_RUN;
            else
              load_idx <= load_idx + 1;
            end if;

          when CH_RUN =>
            core_rst <= '0';
            if core_ov = '1' then
              if cmp_idx < GV_E then
                if core_eb /= exp_bit(cmp_idx) then
                  -- bit mismatch
                  fail_f <= '1';
                  done_f <= '1';
                  chk    <= CH_FAIL;
                elsif cmp_idx = GV_E - 1 then
                  -- last expected bit: it must coincide with `last`.
                  if core_last = '1' then
                    pass_f <= '1';
                    done_f <= '1';
                    chk    <= CH_PASS;
                  else
                    fail_f <= '1';   -- ran long: no `last` at E-1
                    done_f <= '1';
                    chk    <= CH_FAIL;
                  end if;
                  cmp_idx <= cmp_idx + 1;
                else
                  -- matched, not last yet: `last` arriving early is a failure.
                  if core_last = '1' then
                    fail_f <= '1';   -- short: `last` before E-1
                    done_f <= '1';
                    chk    <= CH_FAIL;
                  end if;
                  cmp_idx <= cmp_idx + 1;
                end if;
              else
                -- more output than E bits expected -> failure.
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
