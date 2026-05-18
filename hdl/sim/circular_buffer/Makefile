TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := circular_buffer
COCOTB_TEST_MODULES := test_circular_buffer

VHDL_SOURCES := $(PWD)/../../rtl/circular_buffer.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=circular_buffer.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
