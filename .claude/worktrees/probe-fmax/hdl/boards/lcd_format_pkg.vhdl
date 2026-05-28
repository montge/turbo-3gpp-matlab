library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Tiny shared formatting helper for the DE2 board demos' LCD line-2 status.
--
-- The shared hd44780_lcd controller consumes ASCII character codes, so an
-- integer self-check statistic (the output-bit error count) must be rendered
-- as decimal digits before it can be spliced into a string(1 to 16) line
-- buffer. This package provides one pure function, used by both board wrappers
-- (turbo_decoder_de2_top, tx_chain_de2_top) and the GHDL byte-sequence TBs, so
-- there is a single authoritative definition of the digit conversion.
package lcd_format_pkg is

  -- Render an unsigned value as an n_digits-wide, zero-padded, decimal ASCII
  -- string, most-significant digit first. If the value exceeds the field
  -- (10**n_digits - 1) the result saturates to all-'9's, so the returned
  -- string length is ALWAYS exactly n_digits -- a hard guarantee that the
  -- 16-char LCD line stays 16 chars regardless of a pathological count.
  function uint_to_ascii(value : unsigned; n_digits : integer) return string;

end package lcd_format_pkg;

package body lcd_format_pkg is

  function uint_to_ascii(value : unsigned; n_digits : integer) return string is
    -- 10**n_digits - 1 is the largest value the field can show; above it we
    -- saturate. n_digits is small (3 here) so a plain integer holds the
    -- value/cap without overflow concerns for the bounded board counts.
    variable cap     : integer := 1;
    variable v       : integer;
    variable digit   : integer;
    variable result  : string(1 to n_digits);
  begin
    -- cap = 10**n_digits - 1
    for i in 1 to n_digits loop
      cap := cap * 10;
    end loop;
    cap := cap - 1;

    -- Convert to integer once (values are bounded well under integer'high),
    -- then saturate to the field maximum.
    v := to_integer(value);
    if v > cap then
      v := cap;
    end if;

    -- Emit MSD-first by filling from the least-significant position backward.
    for i in n_digits downto 1 loop
      digit     := v mod 10;
      result(i) := character'val(character'pos('0') + digit);
      v         := v / 10;
    end loop;

    return result;
  end function;

end package body lcd_format_pkg;
