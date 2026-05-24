# DE2 turbo_decoder_top board-demo timing constraints.
#
# The demo is fully synchronous on a PLL-derived ~12.5 MHz clock (CLOCK_50 / 4
# via the altpll wrapper pll_12p5). The 50 MHz CLOCK_50 only feeds the PLL; the
# decoder core + self-check FSM are clocked entirely by the PLL output. The
# decoder's pre-existing ~64.8 ns forward alpha-recurrence cone caps Fmax at
# 15.43 MHz, so TimeQuest must close setup/hold on the 80 ns (12.5 MHz) PLL
# domain -- comfortably over the 64.8 ns critical cone (Option A).

# 50 MHz reference clock on the DE2 oscillator pin (PLL input only).
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Let TimeQuest auto-create the PLL output clock(s) from the altpll
# megafunction parameters (multiply=1 / divide=4 -> 12.5 MHz, 80 ns period).
# This is the source of truth for the derived-domain analysis -- the whole demo
# is constrained on it.
derive_pll_clocks

# Account for clock network / PLL jitter uncertainty on every clock.
derive_clock_uncertainty

# Asynchronous, human-driven / display I/O: false-path them so TimeQuest does
# not flag the unconstrained async KEY input and the LED / 7-seg outputs.
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*]}]
set_false_path -to   [get_ports {LEDG[*]}]
set_false_path -to   [get_ports {HEX0[*]}]
set_false_path -to   [get_ports {HEX1[*]}]
