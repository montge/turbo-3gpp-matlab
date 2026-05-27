library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.lcd_format_pkg.all;   -- uint_to_ascii (the unit under test)

-- Thin GHDL/cocotb harness that unit-checks the shared uint_to_ascii helper.
-- cocotb cannot call a VHDL function directly, so this TB renders a handful of
-- values at elaboration and exposes each 3-char result as three 8-bit ASCII
-- byte ports the cocotb test reads and compares to the expected decimal string:
--
--   d0_*  = uint_to_ascii(0,    3)  -> "000"   (zero)
--   d1_*  = uint_to_ascii(42,   3)  -> "042"   (mid, zero-padded)
--   d2_*  = uint_to_ascii(1234, 3)  -> "999"   (saturation: >999 -> all-9s)
--
-- No clock is needed; the outputs are pure combinational renders of constants.
entity lcd_format_tb_top is
  port (
    -- value 0 -> "000"
    d0_msd : out std_logic_vector(7 downto 0);
    d0_mid : out std_logic_vector(7 downto 0);
    d0_lsd : out std_logic_vector(7 downto 0);
    -- value 42 -> "042"
    d1_msd : out std_logic_vector(7 downto 0);
    d1_mid : out std_logic_vector(7 downto 0);
    d1_lsd : out std_logic_vector(7 downto 0);
    -- value 1234 -> "999" (saturated)
    d2_msd : out std_logic_vector(7 downto 0);
    d2_mid : out std_logic_vector(7 downto 0);
    d2_lsd : out std_logic_vector(7 downto 0)
  );
end entity lcd_format_tb_top;

architecture rtl of lcd_format_tb_top is
  constant S0 : string(1 to 3) := uint_to_ascii(to_unsigned(0,    10), 3);
  constant S1 : string(1 to 3) := uint_to_ascii(to_unsigned(42,   12), 3);
  constant S2 : string(1 to 3) := uint_to_ascii(to_unsigned(1234, 12), 3);

  function chr8(c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function;
begin
  d0_msd <= chr8(S0(1));
  d0_mid <= chr8(S0(2));
  d0_lsd <= chr8(S0(3));

  d1_msd <= chr8(S1(1));
  d1_mid <= chr8(S1(2));
  d1_lsd <= chr8(S1(3));

  d2_msd <= chr8(S2(1));
  d2_mid <= chr8(S2(2));
  d2_lsd <= chr8(S2(3));
end architecture rtl;
