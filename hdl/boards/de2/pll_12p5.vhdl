library ieee;
use ieee.std_logic_1164.all;

-- ===========================================================================
-- pll_12p5 : Cyclone II PLL deriving 12.5 MHz from the 50 MHz CLOCK_50.
--
-- SYNTHESIS architecture (this file). Used ONLY by the Quartus project
-- (turbo_decoder_de2.qsf). It wraps the wizard-generated altpll megafunction
-- pll_12p5_mf.vhd (qmegawiz, Quartus II 13.0sp1, Cyclone II, NORMAL mode,
-- inclk0 = 50 MHz / 20000 ps, one output c0 = 12.5 MHz via the integer ratio
-- multiply=1 / divide=4 -> 80 ns period; the wizard's reported effective output
-- frequency is 12.500000 MHz). The wizard output is committed verbatim and
-- carries the per-clock + lock parameters A&S requires (gate_lock_signal,
-- valid/invalid_lock_multiplier); a hand-rolled altpll GENERIC MAP that omits
-- them is rejected with "uses test-only parameter c0_test_source".
--
-- A divide-by-4 is the first integer-friendly PLL ratio that clears the
-- decoder's 15.43 MHz Fmax ceiling (the constituent core's ~64.8 ns forward
-- alpha-recurrence cone) with comfortable margin: 80 ns period vs the 64.8 ns
-- critical cone leaves ~15 ns raw slack before clock uncertainty. (A divide-by-3
-- -> 16.67 MHz / 60 ns period would FAIL the 64.8 ns cone -- do not use it.)
--
-- GHDL CANNOT elaborate the altpll hard block, so the GHDL self-check lane
-- compiles the SIBLING file pll_12p5_sim.vhdl instead -- a behavioural
-- divide-by-4 clock divider exposing the identical entity. The whole demo is
-- synchronous, so a divided sim clock is functionally equivalent for the
-- bit-exact self-check; only Quartus elaborates the real PLL.
--
-- Port contract (shared by both architectures and by pll_12p5_mf):
--   areset  : in   async PLL reset (active high; tie '0' for free-run)
--   inclk0  : in   50 MHz reference (CLOCK_50)
--   c0      : out  12.5 MHz derived clock (drives the whole demo)
--   locked  : out  PLL lock indicator ('1' once locked)
-- ===========================================================================
entity pll_12p5 is
  port (
    areset : in  std_logic := '0';
    inclk0 : in  std_logic;
    c0     : out std_logic;
    locked : out std_logic
  );
end entity pll_12p5;

architecture syn of pll_12p5 is
  component pll_12p5_mf is
    port (
      areset : in  std_logic := '0';
      inclk0 : in  std_logic := '0';
      c0     : out std_logic;
      locked : out std_logic
    );
  end component;
begin
  u_mf : pll_12p5_mf
    port map (
      areset => areset,
      inclk0 => inclk0,
      c0     => c0,
      locked => locked
    );
end architecture syn;
