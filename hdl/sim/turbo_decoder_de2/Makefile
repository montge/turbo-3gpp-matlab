TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := turbo_decoder_de2_top
COCOTB_TEST_MODULES := test_turbo_decoder_de2

# Iterative turbo-decoder RTL (unmodified) + shared hex decoder + board golden
# ROM package + the SIM PLL (behavioural /2 divider; GHDL cannot elaborate the
# Altera altpll hard block, so pll_25_sim.vhdl replaces pll_25.vhdl here) +
# board wrapper. The wrapper instantiates turbo_decoder_top as a component;
# nothing under hdl/rtl/ is edited by this lane.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/constituent_decoder.vhdl \
                $(PWD)/../../rtl/turbo_decoder_top.vhdl \
                $(PWD)/../../boards/hex7seg.vhdl \
                $(PWD)/../../boards/lcd_format_pkg.vhdl \
                $(PWD)/../../boards/hd44780_lcd.vhdl \
                $(PWD)/../../boards/de2/pll_25_sim.vhdl \
                $(PWD)/../../boards/de2/turbo_decoder_golden_pkg.vhdl \
                $(PWD)/../../boards/de2/turbo_decoder_de2_top.vhdl

EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=turbo_decoder_de2_top.vcd

# Default lane = the real board behaviour (CORRUPT_IDX=-1) -> must PASS.
# The corrupted-bit FAIL proof is driven by test_runner.py (re-elaborates with
# a flipped expected bit). COCOTB_EXPECT tells the test which verdict to assert.
export COCOTB_EXPECT ?= pass

include $(shell cocotb-config --makefiles)/Makefile.sim
