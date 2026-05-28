library ieee;
use ieee.std_logic_1164.all;

entity and2 is
  port (
    a_i : in  std_logic;
    b_i : in  std_logic;
    y_o : out std_logic
  );
end entity and2;

architecture rtl of and2 is
begin
  y_o <= a_i and b_i;
end architecture rtl;

