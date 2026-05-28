TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := rate_matching_top
COCOTB_TEST_MODULES := test_rate_matching_top

VHDL_SOURCES := $(PWD)/../../rtl/subblock_interleaver.vhdl \
                $(PWD)/../../rtl/circular_buffer.vhdl \
                $(PWD)/../../rtl/rate_matching_top.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=rate_matching_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
