library ieee;
use ieee.std_logic_1164.all;

-- Altera DE1 (Cyclone II EP2C20F484C7) board wrapper for the verified
-- crc8_parallel core. The core is instantiated unmodified; this wrapper only
-- adapts board I/O. The DE1 has only 10 toggle switches, so SW[7:0] drive an
-- 8-bit, zero-extended core input; the 8-bit CRC is shown on HEX1/HEX0 and
-- mirrored on LEDR[7:0]. A full 16-bit KEY-latched loader is a documented
-- optional follow-on, intentionally out of scope here.
entity crc8_de1_top is
  port (
    SW   : in  std_logic_vector(7 downto 0);
    LEDR : out std_logic_vector(7 downto 0);
    HEX0 : out std_logic_vector(6 downto 0);
    HEX1 : out std_logic_vector(6 downto 0)
  );
end entity crc8_de1_top;

architecture rtl of crc8_de1_top is
  component crc8_parallel is
    port (
      data_i : in  std_logic_vector(15 downto 0);
      crc_o  : out std_logic_vector(7 downto 0)
    );
  end component;

  component hex7seg is
    port (
      nibble_i : in  std_logic_vector(3 downto 0);
      seg_o    : out std_logic_vector(6 downto 0)
    );
  end component;

  signal data16 : std_logic_vector(15 downto 0);
  signal crc    : std_logic_vector(7 downto 0);
begin
  data16 <= "00000000" & SW;

  u_core : crc8_parallel
    port map (
      data_i => data16,
      crc_o  => crc
    );

  u_hex0 : hex7seg
    port map (
      nibble_i => crc(3 downto 0),
      seg_o    => HEX0
    );

  u_hex1 : hex7seg
    port map (
      nibble_i => crc(7 downto 4),
      seg_o    => HEX1
    );

  LEDR <= crc;
end architecture rtl;
