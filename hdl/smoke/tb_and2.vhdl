library ieee;
use ieee.std_logic_1164.all;

entity tb_and2 is
end entity tb_and2;

architecture sim of tb_and2 is
  signal a_s : std_logic := '0';
  signal b_s : std_logic := '0';
  signal y_s : std_logic;
begin
  dut : entity work.and2
    port map (
      a_i => a_s,
      b_i => b_s,
      y_o => y_s
    );

  stimulus : process
  begin
    a_s <= '0';
    b_s <= '0';
    wait for 1 ns;
    assert y_s = '0' report "0 and 0 should be 0" severity error;

    a_s <= '1';
    b_s <= '0';
    wait for 1 ns;
    assert y_s = '0' report "1 and 0 should be 0" severity error;

    a_s <= '0';
    b_s <= '1';
    wait for 1 ns;
    assert y_s = '0' report "0 and 1 should be 0" severity error;

    a_s <= '1';
    b_s <= '1';
    wait for 1 ns;
    assert y_s = '1' report "1 and 1 should be 1" severity error;

    report "GHDL smoke test passed" severity note;
    wait;
  end process stimulus;
end architecture sim;

