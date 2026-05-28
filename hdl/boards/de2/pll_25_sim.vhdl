library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- pll_25 (SIMULATION architecture) : behavioural divide-by-2 clock divider
-- exposing the SAME entity as the synthesis altpll wrapper (pll_25.vhdl).
--
-- GHDL cannot elaborate the Cyclone II `altpll` hard block, so the GHDL
-- self-check lane (hdl/sim/turbo_decoder_de2/) compiles THIS file in place of
-- pll_25.vhdl. It produces c0 = inclk0 / 2 (a real 50 MHz testbench clock
-- becomes the functional 25 MHz demo clock) and asserts `locked` immediately.
-- The demo is fully synchronous, so the divided sim clock is functionally
-- identical to the synthesised PLL output for the bit-exact self-check; the
-- real PLL is exercised only by Quartus elaboration and the on-board run.
--
-- NOTE: exactly ONE of pll_25.vhdl (synth) / pll_25_sim.vhdl (sim) is compiled
-- per flow -- the .qsf lists the altpll wrapper, the GHDL Makefile lists this
-- divider. Both declare entity pll_25 with the identical port.
-- ===========================================================================
entity pll_25 is
  port (
    areset : in  std_logic := '0';
    inclk0 : in  std_logic;
    c0     : out std_logic;
    locked : out std_logic
  );
end entity pll_25;

architecture sim of pll_25 is
  signal clk_q : std_logic := '0';
begin
  -- Divide inclk0 by 2: toggle the output on every input rising edge, giving a
  -- symmetric /2 clock (50 MHz -> 25 MHz, 40 ns period).
  process (inclk0)
  begin
    if rising_edge(inclk0) then
      clk_q <= not clk_q;
    end if;
  end process;

  c0     <= clk_q;
  locked <= '1';            -- behavioural model: locked from t=0
end architecture sim;
