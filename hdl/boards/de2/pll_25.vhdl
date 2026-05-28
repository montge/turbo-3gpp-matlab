library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- pll_25 : Cyclone II PLL deriving 25 MHz from the 50 MHz CLOCK_50.
--
-- SYNTHESIS architecture (this file). Used ONLY by the Quartus project
-- (turbo_decoder_de2.qsf). It wraps the altpll megafunction pll_25_mf.vhd
-- (hand-adapted from the validated pll_12p5_mf wizard output: NORMAL mode,
-- inclk0 = 50 MHz / 20000 ps, one output c0 = 25 MHz via the integer ratio
-- multiply=1 / divide=2 -> 40 ns period; effective output 25.000000 MHz).
--
-- A divide-by-2 (25 MHz / 40 ns) is the board clock for the
-- add-fpga-decoder-recurrence-pipelining build: with the anchor-norm +
-- balanced-tree-fold + pipelined-delta-fold levers enabled, the decoder's
-- restricted Fmax is 27.63 MHz, so 25 MHz closes with ~2.6 MHz margin. This
-- replaces the prior divide-by-4 (12.5 MHz) Option-A workaround now that the
-- recurrence/fold cones are shortened.
--
-- GHDL cannot elaborate the altpll hard block, so the GHDL self-check lane
-- compiles the SIBLING file pll_25_sim.vhdl (a behavioural divide-by-2 clock
-- divider exposing the identical entity) instead. The whole demo is
-- synchronous, so a divided sim clock is functionally equivalent for the
-- bit-exact self-check; only Quartus elaborates the real PLL.
--
-- Port contract (shared by both architectures and by pll_25_mf):
--   areset  : in   async PLL reset (active high; tie '0' for free-run)
--   inclk0  : in   50 MHz reference (CLOCK_50)
--   c0      : out  25 MHz derived clock (drives the whole demo)
--   locked  : out  PLL lock indicator ('1' once locked)
-- ===========================================================================
entity pll_25 is
  port (
    areset : in  std_logic := '0';
    inclk0 : in  std_logic;
    c0     : out std_logic;
    locked : out std_logic
  );
end entity pll_25;

architecture syn of pll_25 is
  component pll_25_mf is
    port (
      areset : in  std_logic := '0';
      inclk0 : in  std_logic := '0';
      c0     : out std_logic;
      locked : out std_logic
    );
  end component;
begin
  u_mf : pll_25_mf
    port map (
      areset => areset,
      inclk0 => inclk0,
      c0     => c0,
      locked => locked
    );
end architecture syn;
