TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := tx_chain_de2_top
COCOTB_TEST_MODULES := test_tx_chain_de2

# Hardened TX-chain RTL (unmodified) + shared hex decoder + board golden ROM
# package + board wrapper. The wrapper instantiates tx_chain_top as a
# component; nothing under hdl/rtl/ is edited by this lane.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/rsc_constituent_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encode_top.vhdl \
                $(PWD)/../../rtl/subblock_interleaver.vhdl \
                $(PWD)/../../rtl/circular_buffer.vhdl \
                $(PWD)/../../rtl/rate_matching_top.vhdl \
                $(PWD)/../../rtl/tx_chain_top.vhdl \
                $(PWD)/../../boards/hex7seg.vhdl \
                $(PWD)/../../boards/de2/tx_chain_golden_pkg.vhdl \
                $(PWD)/../../boards/de2/tx_chain_de2_top.vhdl

EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=tx_chain_de2_top.vcd

# Default lane = the real board behaviour (CORRUPT_IDX=-1) -> must PASS.
# The corrupted-bit FAIL proof is driven by test_runner.py (re-elaborates with
# a flipped expected bit). COCOTB_EXPECT tells the test which verdict to assert.
export COCOTB_EXPECT ?= pass

include $(shell cocotb-config --makefiles)/Makefile.sim
