library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- kr260_clocking_wrapper (SIMULATION architecture)
-- ---------------------------------------------------------------------------
-- Behavioural stand-in for the Vivado-generated Zynq MPSoC block-design wrapper
-- (kr260_clocking_wrapper, produced by `make_wrapper -import` in
-- turbo_decoder_kr260_synth.tcl). GHDL cannot elaborate the zynq_ultra_ps_e PS
-- hard block, so the KR260 self-check lane (hdl/sim/turbo_decoder_kr260/)
-- compiles THIS file in place of the generated <bd>_wrapper.vhd -- the Xilinx
-- analog of the DE2 lane swapping pll_25_sim.vhdl for the Altera altpll wrapper.
--
-- It exposes the SAME entity name + ports as the component that
-- turbo_decoder_kr260_top.vhdl instantiates: two OUTPUTS (pl_clk0, pl_resetn0)
-- and NO inputs -- the real PS sources the PL clock internally from its PLLs, so
-- there is no clock input pin. This stub therefore SELF-GENERATES the clock with
-- an `after` driver (there is no input clock to divide, unlike the DE2 /2 PLL).
--
--   * pl_clk0    : free-running 100 MHz (10 ns period) -- matches the PS preset
--                  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ=100.
--   * pl_resetn0 : active-LOW; asserted (0) for a few cycles then released (1),
--                  modelling proc_sys_reset's peripheral_aresetn coming out of
--                  reset shortly after the clock is stable.
--
-- The demo is fully synchronous, so this behavioural clock is functionally
-- identical to the real PS pl_clk0 for the bit-exact self-check verdict; the
-- real PS block is exercised only by the Vivado build and the on-board run.
-- ===========================================================================
entity kr260_clocking_wrapper is
  port (
    pl_clk0    : out std_logic;
    pl_resetn0 : out std_logic
  );
end entity kr260_clocking_wrapper;

architecture sim of kr260_clocking_wrapper is
  signal clk_i  : std_logic := '0';
  signal rstn_i : std_logic := '0';
begin
  -- 100 MHz free-running clock (10 ns period, 5 ns half-period).
  clk_i   <= not clk_i after 5 ns;
  pl_clk0 <= clk_i;

  -- proc_sys_reset analog: hold reset asserted (active-low => '0') for ~5
  -- cycles, then release and stay released for the rest of the simulation.
  process
  begin
    rstn_i <= '0';
    wait for 53 ns;          -- ~5 clk cycles after t=0
    rstn_i <= '1';
    wait;
  end process;
  pl_resetn0 <= rstn_i;
end architecture sim;
