library ieee;
use ieee.std_logic_1164.all;

-- GHDL/cocotb test harnesses for the shared hd44780_lcd controller.
--
-- cocotb cannot conveniently drive a VHDL `string(1 to 16)` port, so these thin
-- tops wrap hd44780_lcd, fix the two line buffers to a known sample message, and
-- expose the LCD bus + clk/rst as std_logic(_vector) ports cocotb can read.
--
-- The controller derives every HD44780 delay counter from a CLK_HZ generic. The
-- robust way to exercise the scaling under GHDL mcode is to bake CLK_HZ at each
-- instance's generic map (a run-step top-level -g override does NOT recompute
-- the generic-derived elaboration constants under mcode), so this file provides
-- TWO fixed-frequency tops the runner selects via TOPLEVEL:
--
--   hd44780_lcd_tb_top  -> CLK_HZ = 12_500_000 (the decoder demo domain)
--   hd44780_lcd_tb_fast -> CLK_HZ = 50_000_000 (the TX demo domain)
--
-- Both emit the identical byte sequence; their realized power-on settle differs
-- by the 4:1 frequency ratio, which the cocotb test asserts against
-- ceil(CLK_HZ * us / 1e6) -- proving the generic delay scaling in simulation.
--
-- Sample message (must match the byte sequence the cocotb test asserts):
--   line 1 = "HELLO LCD WORLD!"  (16 chars)
--   line 2 = "0123456789ABCDEF"  (16 chars)

----------------------------------------------------------------------------
-- 12.5 MHz harness (default cocotb top).
----------------------------------------------------------------------------
entity hd44780_lcd_tb_top is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    lcd_data : out std_logic_vector(7 downto 0);
    lcd_rs   : out std_logic;
    lcd_rw   : out std_logic;
    lcd_en   : out std_logic;
    lcd_on   : out std_logic;
    lcd_blon : out std_logic
  );
end entity hd44780_lcd_tb_top;

architecture rtl of hd44780_lcd_tb_top is
  component hd44780_lcd is
    generic (CLK_HZ : integer := 50_000_000);
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
  constant LINE1 : string(1 to 16) := "HELLO LCD WORLD!";
  constant LINE2 : string(1 to 16) := "0123456789ABCDEF";
begin
  u_lcd : hd44780_lcd
    generic map (CLK_HZ => 12_500_000)
    port map (
      clk => clk, rst => rst, line1_i => LINE1, line2_i => LINE2,
      lcd_data => lcd_data, lcd_rs => lcd_rs, lcd_rw => lcd_rw,
      lcd_en => lcd_en, lcd_on => lcd_on, lcd_blon => lcd_blon
    );
end architecture rtl;

----------------------------------------------------------------------------
-- 50 MHz harness (selected by the runner's second case via TOPLEVEL).
----------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity hd44780_lcd_tb_fast is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    lcd_data : out std_logic_vector(7 downto 0);
    lcd_rs   : out std_logic;
    lcd_rw   : out std_logic;
    lcd_en   : out std_logic;
    lcd_on   : out std_logic;
    lcd_blon : out std_logic
  );
end entity hd44780_lcd_tb_fast;

architecture rtl of hd44780_lcd_tb_fast is
  component hd44780_lcd is
    generic (CLK_HZ : integer := 50_000_000);
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
  constant LINE1 : string(1 to 16) := "HELLO LCD WORLD!";
  constant LINE2 : string(1 to 16) := "0123456789ABCDEF";
begin
  u_lcd : hd44780_lcd
    generic map (CLK_HZ => 50_000_000)
    port map (
      clk => clk, rst => rst, line1_i => LINE1, line2_i => LINE2,
      lcd_data => lcd_data, lcd_rs => lcd_rs, lcd_rw => lcd_rw,
      lcd_en => lcd_en, lcd_on => lcd_on, lcd_blon => lcd_blon
    );
end architecture rtl;
