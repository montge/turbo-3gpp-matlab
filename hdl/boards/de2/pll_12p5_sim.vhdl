library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- pll_12p5 (SIMULATION architecture) : behavioural divide-by-4 clock divider
-- exposing the SAME entity as the synthesis altpll wrapper (pll_12p5.vhdl).
--
-- GHDL cannot elaborate the Cyclone II `altpll` hard block, so the GHDL
-- self-check lane (hdl/sim/turbo_decoder_de2/) compiles THIS file in place of
-- pll_12p5.vhdl. It produces c0 = inclk0 / 4 (a real 50 MHz testbench clock
-- becomes the functional 12.5 MHz demo clock) and asserts `locked` immediately.
-- The demo is fully synchronous, so the divided sim clock is functionally
-- identical to the synthesised PLL output for the bit-exact self-check; the
-- real PLL is exercised only by Quartus elaboration and the on-board run.
--
-- NOTE: exactly ONE of pll_12p5.vhdl (synth) / pll_12p5_sim.vhdl (sim) is
-- compiled per flow -- the .qsf lists the altpll wrapper, the GHDL Makefile
-- lists this divider. Both declare entity pll_12p5 with the identical port.
-- ===========================================================================
entity pll_12p5 is
  port (
    areset : in  std_logic := '0';
    inclk0 : in  std_logic;
    c0     : out std_logic;
    locked : out std_logic
  );
end entity pll_12p5;

architecture sim of pll_12p5 is
  signal divcnt : unsigned(1 downto 0) := (others => '0');
  signal clk_q  : std_logic := '0';
begin
  -- Divide inclk0 by 4: toggle the output every 2 input edges (count 0..3,
  -- flip clk_q at the half-period). divcnt rolls 0->1->2->3->0; clk_q toggles
  -- on the wrap to give a symmetric /4 clock.
  process (inclk0)
  begin
    if rising_edge(inclk0) then
      if divcnt = 1 then
        clk_q  <= not clk_q;
        divcnt <= (others => '0');
      else
        divcnt <= divcnt + 1;
      end if;
    end if;
  end process;

  c0     <= clk_q;
  locked <= '1';            -- behavioural model: locked from t=0
end architecture sim;
