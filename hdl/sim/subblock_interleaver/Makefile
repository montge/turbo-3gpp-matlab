TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := subblock_interleaver
COCOTB_TEST_MODULES := test_subblock_interleaver

VHDL_SOURCES := $(PWD)/../../rtl/subblock_interleaver.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=subblock_interleaver.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
