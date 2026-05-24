TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := de_rate_matching_top
COCOTB_TEST_MODULES := test_de_rate_matching_top

# The de-rate-match top reuses the UNMODIFIED subblock_interleaver (address +
# filler generator, direction-agnostic) and instantiates the new soft-mirror
# de_circular_buffer; analyze the sub-cores before the integrating top (GHDL
# elaboration order), exactly as rate_matching_top compiles its sub-cores.
VHDL_SOURCES := $(PWD)/../../rtl/subblock_interleaver.vhdl \
                $(PWD)/../../rtl/de_circular_buffer.vhdl \
                $(PWD)/../../rtl/de_rate_matching_top.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=de_rate_matching_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
