TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := tx_chain_top
COCOTB_TEST_MODULES := test_tx_chain_top

# Package + all leaf cores + sub-tops before the chain top.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/rsc_constituent_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encode_top.vhdl \
                $(PWD)/../../rtl/subblock_interleaver.vhdl \
                $(PWD)/../../rtl/circular_buffer.vhdl \
                $(PWD)/../../rtl/rate_matching_top.vhdl \
                $(PWD)/../../rtl/tx_chain_top.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=tx_chain_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
