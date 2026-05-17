library ieee;
use ieee.std_logic_1164.all;

-- Nibble to seven-segment decoder for Terasic DE-series HEX displays.
-- Segments are active-low (a driven '0' lights the segment).
-- seg_o(0)=a, seg_o(1)=b, ... seg_o(6)=g (Terasic HEX[6:0] convention).
entity hex7seg is
  port (
    nibble_i : in  std_logic_vector(3 downto 0);
    seg_o    : out std_logic_vector(6 downto 0)
  );
end entity hex7seg;

architecture rtl of hex7seg is
begin
  with nibble_i select
    seg_o <=
      "1000000" when "0000",  -- 0
      "1111001" when "0001",  -- 1
      "0100100" when "0010",  -- 2
      "0110000" when "0011",  -- 3
      "0011001" when "0100",  -- 4
      "0010010" when "0101",  -- 5
      "0000010" when "0110",  -- 6
      "1111000" when "0111",  -- 7
      "0000000" when "1000",  -- 8
      "0010000" when "1001",  -- 9
      "0001000" when "1010",  -- A
      "0000011" when "1011",  -- b
      "1000110" when "1100",  -- C
      "0100001" when "1101",  -- d
      "0000110" when "1110",  -- E
      "0001110" when "1111",  -- F
      "1111111" when others;  -- blank on metavalue inputs
end architecture rtl;
