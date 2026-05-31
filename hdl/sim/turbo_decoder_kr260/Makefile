TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := turbo_decoder_kr260_top
COCOTB_TEST_MODULES := test_turbo_decoder_kr260

# Iterative turbo-decoder RTL (unmodified) + the shared on-chip golden ROM
# package (reused from the DE2 board build -- same K=512, max_iter=2 row) + the
# SIM clocking stub (behavioural self-clocking stand-in for the Vivado Zynq PS
# block-design wrapper; GHDL cannot elaborate zynq_ultra_ps_e, so
# kr260_clocking_wrapper_sim.vhdl replaces the generated <bd>_wrapper.vhd here)
# + the KR260 board wrapper. The wrapper instantiates turbo_decoder_top as a
# component; nothing under hdl/rtl/ is edited by this lane.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/constituent_decoder.vhdl \
                $(PWD)/../../rtl/turbo_decoder_top.vhdl \
                $(PWD)/../../boards/de2/turbo_decoder_golden_pkg.vhdl \
                $(PWD)/../../boards/kr260/kr260_clocking_wrapper_sim.vhdl \
                $(PWD)/../../boards/kr260/turbo_decoder_kr260_top.vhdl

EXTRA_ARGS += --std=08

# The KR260 top exposes ONLY the two status LEDs (no clock/done port) -- the PL
# clock is self-generated inside the sim stub. The encoded LED outputs depend on
# the run-hold window, which defaults to ~1.5 s (150M cycles) on the board;
# shrink it to a few cycles in sim so the latched verdict becomes visible on the
# LEDs well within the cocotb cycle budget.
SIM_ARGS += -gRUN_HOLD_CYC_OVR=8
SIM_ARGS += --vcd=turbo_decoder_kr260_top.vcd

# Default lane = the real board behaviour (CORRUPT_IDX=-1) -> must PASS. The
# corrupted-bit FAIL proof is driven by test_runner.py (re-elaborates with a
# flipped expected bit). COCOTB_EXPECT tells the test which verdict to assert.
export COCOTB_EXPECT ?= pass

include $(shell cocotb-config --makefiles)/Makefile.sim
