TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := constituent_decoder
COCOTB_TEST_MODULES := test_constituent_decoder

VHDL_SOURCES := $(PWD)/../../rtl/constituent_decoder.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=constituent_decoder.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
