TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := qpp_interleaver
COCOTB_TEST_MODULES := test_qpp_interleaver

VHDL_SOURCES := $(PWD)/../../rtl/qpp_interleaver.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=qpp_interleaver.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
