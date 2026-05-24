library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- Shared HD44780-compatible 16x2 character-LCD controller for the Terasic
-- DE-series on-board LCD. A reusable board component (sibling of
-- hdl/boards/hex7seg.vhdl), referenced -- not copied -- by each demo .qsf.
--
-- The controller runs the documented HD44780 cold-start init sequence, then
-- continuously refreshes the two 16-character line buffers to DDRAM. The bus is
-- write-only (lcd_rw tied '0'): rather than poll the busy flag we wait the
-- documented worst-case post-command delays, which is simpler and robust.
--
--   Init (on power-up and on every rst):
--     1. wait >= 15 ms (power-on settle)
--     2. function-set  : 0x38  (8-bit interface, 2 lines, 5x8 font)
--     3. display-on    : 0x0C  (display on, cursor off, blink off)
--     4. display-clear : 0x01  (clear, returns home; needs ~1.5 ms)
--     5. entry-mode    : 0x06  (increment address, no display shift)
--   Refresh (forever after init):
--     set-DDRAM 0x80 (addr 0x00) then 16 data bytes of line1_i;
--     set-DDRAM 0xC0 (addr 0x40) then 16 data bytes of line2_i; loop.
--
-- Every delay is counter-based and scaled from the CLK_HZ generic
--   cycles = ceil(CLK_HZ * delay_us / 1_000_000)
-- so one core serves the 50 MHz TX domain and the 12.5 MHz decoder domain by
-- construction. Counter width is sized for the worst case (the ~15 ms power-on
-- wait at the highest supported clock).
--
-- E-strobe framing per write: hold lcd_rs/lcd_data stable, raise lcd_en for an
-- enable-high window (>= ~1 us worst case), lower it, then wait the command's
-- post-write busy delay before the next write. lcd_on / lcd_blon are tied '1'
-- (panel power + backlight on).
entity hd44780_lcd is
  generic (
    -- Functional clock frequency in Hz; scales every HD44780 delay counter.
    -- 50_000_000 for the TX demo, 12_500_000 for the decoder demo.
    CLK_HZ : integer := 50_000_000
  );
  port (
    clk      : in  std_logic;                     -- demo functional clock
    rst      : in  std_logic;                     -- sync reset: re-run init
    line1_i  : in  string(1 to 16);               -- top line ASCII (label)
    line2_i  : in  string(1 to 16);               -- bottom line ASCII (status)
    -- HD44780 8-bit parallel bus to the DE2 LCD header:
    lcd_data : out std_logic_vector(7 downto 0);  -- DB7..DB0
    lcd_rs   : out std_logic;                      -- 0 = command, 1 = data
    lcd_rw   : out std_logic;                      -- tied 0 (write-only)
    lcd_en   : out std_logic;                      -- E strobe
    lcd_on   : out std_logic;                      -- panel power (driven '1')
    lcd_blon : out std_logic                       -- backlight (driven '1')
  );
end entity hd44780_lcd;

architecture rtl of hd44780_lcd is

  ---------------------------------------------------------------------------
  -- Delay-count helper: ceil(CLK_HZ * us / 1e6), clamped to >= 1 cycle.
  ---------------------------------------------------------------------------
  function us_cycles(us : integer) return integer is
    -- Use real to avoid integer overflow of CLK_HZ*us at high frequencies.
    variable c : integer;
  begin
    c := integer(ceil((real(CLK_HZ) * real(us)) / 1.0e6));
    if c < 1 then
      return 1;
    else
      return c;
    end if;
  end function;

  -- Documented HD44780 timing windows (worst-case, write-only):
  --   power-on settle       : >= 15 ms  -> use 20 ms for margin
  --   clear/return-home      : ~1.52 ms -> use 2 ms
  --   ordinary command/data  : ~37 us   -> use 50 us
  --   enable-high pulse       : >= 230 ns at 5V; 1 us is safe at any clk
  constant C_POWERON : integer := us_cycles(20_000);
  constant C_CLEAR   : integer := us_cycles(2_000);
  constant C_SHORT   : integer := us_cycles(50);
  constant C_EN      : integer := us_cycles(1);

  -- Widest counter we ever load is the power-on wait at the highest clock.
  -- Sized from C_POWERON at this instantiation's CLK_HZ.
  function clog2(n : integer) return integer is
    variable v : integer := n - 1;
    variable r : integer := 0;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;
    if r < 1 then
      return 1;
    else
      return r;
    end if;
  end function;
  constant CNT_W : integer := clog2(C_POWERON + 1);

  ---------------------------------------------------------------------------
  -- Init step ROM: each entry is (rs, byte, post-delay-cycles).
  -- rs = '0' command, '1' data. All init steps are commands.
  ---------------------------------------------------------------------------
  -- Phases of the controller.
  type phase_t is (
    PH_POWERON,   -- initial >=15 ms wait before the first write
    PH_INIT,      -- step through the init command ROM
    PH_SET1,      -- set DDRAM to line-1 base (0x80)
    PH_WR1,       -- write 16 line1_i data bytes
    PH_SET2,      -- set DDRAM to line-2 base (0xC0)
    PH_WR2        -- write 16 line2_i data bytes
  );
  signal phase : phase_t := PH_POWERON;

  -- Write micro-sequencer: each byte is emitted as
  --   W_SETUP -> W_EN_HI -> W_EN_LO -> W_HOLD (post-command busy wait)
  type wstate_t is (W_IDLE, W_SETUP, W_EN_HI, W_EN_LO, W_HOLD);
  signal wstate : wstate_t := W_IDLE;

  -- Number of init commands.
  constant N_INIT : integer := 4;            -- func-set, disp-on, clear, entry
  signal init_idx : integer range 0 to N_INIT := 0;
  signal char_idx : integer range 0 to 16 := 0;   -- char within a line

  -- Latched byte to emit and its routing / post-delay for the current write.
  signal cur_data : std_logic_vector(7 downto 0) := (others => '0');
  signal cur_rs   : std_logic := '0';
  signal cur_dly  : integer range 0 to C_POWERON := 0;

  -- Power-on settle counter. Initialized to the full power-on count so the
  -- >=15 ms cold-start wait runs even before any clean reset pulse arrives
  -- (e.g. when rst sits at 'U'/'X' at simulation start, or at FPGA power-up
  -- before the first KEY restart). The reset branch reloads it so a KEY restart
  -- re-runs the full init too.
  signal dly_cnt : unsigned(CNT_W-1 downto 0) := to_unsigned(C_POWERON, CNT_W);

  -- Registered bus drivers.
  signal r_data : std_logic_vector(7 downto 0) := (others => '0');
  signal r_rs   : std_logic := '0';
  signal r_en   : std_logic := '0';

  -- Request-a-write handshake between the phase FSM and the write sequencer.
  signal wr_req  : std_logic := '0';

  -- Init command byte for a given index.
  function init_byte(i : integer) return std_logic_vector is
  begin
    case i is
      when 0      => return x"38";   -- function-set: 8-bit, 2-line, 5x8
      when 1      => return x"0C";   -- display on, cursor off, blink off
      when 2      => return x"01";   -- display clear (long delay)
      when others => return x"06";   -- entry-mode: increment, no shift
    end case;
  end function;

  function init_delay(i : integer) return integer is
  begin
    if i = 2 then
      return C_CLEAR;                -- clear needs ~1.5 ms
    else
      return C_SHORT;
    end if;
  end function;

  -- ASCII code of a string char as an 8-bit vector.
  function chr(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;

begin
  ---------------------------------------------------------------------------
  -- Static panel-power / backlight / write-direction lines.
  ---------------------------------------------------------------------------
  lcd_on   <= '1';
  lcd_blon <= '1';
  lcd_rw   <= '0';

  lcd_data <= r_data;
  lcd_rs   <= r_rs;
  lcd_en   <= r_en;

  ---------------------------------------------------------------------------
  -- Main sequencer. The phase FSM decides WHICH byte to emit next and the
  -- write sub-FSM performs the E-strobe framing + post-command delay.
  ---------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase    <= PH_POWERON;
        wstate   <= W_IDLE;
        init_idx <= 0;
        char_idx <= 0;
        dly_cnt  <= to_unsigned(C_POWERON, CNT_W);
        r_en     <= '0';
        r_rs     <= '0';
        r_data   <= (others => '0');
      else
        case wstate is
          --------------------------------------------------------------
          -- W_IDLE: pick the next byte from the phase FSM. The phase FSM
          -- sets cur_data/cur_rs/cur_dly and raises wr_req when it has a
          -- byte ready; on power-on we first burn the long settle delay.
          --------------------------------------------------------------
          when W_IDLE =>
            r_en <= '0';
            if phase = PH_POWERON then
              -- power-on settle wait, then advance to the init ROM.
              if dly_cnt = 0 then
                phase    <= PH_INIT;
                init_idx <= 0;
              else
                dly_cnt <= dly_cnt - 1;
              end if;
            elsif wr_req = '1' then
              -- latch the byte the phase FSM staged and start the strobe.
              r_data  <= cur_data;
              r_rs    <= cur_rs;
              wstate  <= W_SETUP;
            end if;

          --------------------------------------------------------------
          -- W_SETUP: data/rs are stable (registered last cycle); raise E.
          --------------------------------------------------------------
          when W_SETUP =>
            r_en    <= '1';
            dly_cnt <= to_unsigned(C_EN, CNT_W);
            wstate  <= W_EN_HI;

          --------------------------------------------------------------
          -- W_EN_HI: hold E high for the enable-high window.
          --------------------------------------------------------------
          when W_EN_HI =>
            if dly_cnt = 0 then
              r_en    <= '0';                    -- falling edge latches the byte
              dly_cnt <= to_unsigned(C_EN, CNT_W);
              wstate  <= W_EN_LO;
            else
              dly_cnt <= dly_cnt - 1;
            end if;

          --------------------------------------------------------------
          -- W_EN_LO: short E-low hold, then the post-command busy wait.
          --------------------------------------------------------------
          when W_EN_LO =>
            if dly_cnt = 0 then
              dly_cnt <= to_unsigned(cur_dly, CNT_W);
              wstate  <= W_HOLD;
            else
              dly_cnt <= dly_cnt - 1;
            end if;

          --------------------------------------------------------------
          -- W_HOLD: wait the command's post-write delay, then this write
          -- is complete -> advance the phase FSM bookkeeping.
          --------------------------------------------------------------
          when W_HOLD =>
            if dly_cnt = 0 then
              wstate <= W_IDLE;
              -- advance the phase position now that the byte is done.
              case phase is
                when PH_INIT =>
                  if init_idx = N_INIT - 1 then
                    phase    <= PH_SET1;
                    init_idx <= 0;
                  else
                    init_idx <= init_idx + 1;
                  end if;
                when PH_SET1 =>
                  phase    <= PH_WR1;
                  char_idx <= 0;
                when PH_WR1 =>
                  if char_idx = 15 then
                    phase    <= PH_SET2;
                    char_idx <= 0;
                  else
                    char_idx <= char_idx + 1;
                  end if;
                when PH_SET2 =>
                  phase    <= PH_WR2;
                  char_idx <= 0;
                when PH_WR2 =>
                  if char_idx = 15 then
                    phase    <= PH_SET1;   -- loop: continuous refresh
                    char_idx <= 0;
                  else
                    char_idx <= char_idx + 1;
                  end if;
                when others =>
                  null;
              end case;
            else
              dly_cnt <= dly_cnt - 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Combinational staging: present the next byte + its rs + post-delay for
  -- the current phase position, and assert wr_req in the writeable phases.
  ---------------------------------------------------------------------------
  process (phase, init_idx, char_idx, line1_i, line2_i)
  begin
    cur_data <= (others => '0');
    cur_rs   <= '0';
    cur_dly  <= C_SHORT;
    wr_req   <= '0';

    case phase is
      when PH_POWERON =>
        wr_req <= '0';

      when PH_INIT =>
        cur_data <= init_byte(init_idx);
        cur_rs   <= '0';                       -- command
        cur_dly  <= init_delay(init_idx);
        wr_req   <= '1';

      when PH_SET1 =>
        cur_data <= x"80";                     -- set DDRAM addr 0x00 (line 1)
        cur_rs   <= '0';
        cur_dly  <= C_SHORT;
        wr_req   <= '1';

      when PH_WR1 =>
        cur_data <= chr(line1_i(char_idx + 1)); -- string is 1-based
        cur_rs   <= '1';                        -- data
        cur_dly  <= C_SHORT;
        wr_req   <= '1';

      when PH_SET2 =>
        cur_data <= x"C0";                     -- set DDRAM addr 0x40 (line 2)
        cur_rs   <= '0';
        cur_dly  <= C_SHORT;
        wr_req   <= '1';

      when PH_WR2 =>
        cur_data <= chr(line2_i(char_idx + 1));
        cur_rs   <= '1';
        cur_dly  <= C_SHORT;
        wr_req   <= '1';
    end case;
  end process;

end architecture rtl;
