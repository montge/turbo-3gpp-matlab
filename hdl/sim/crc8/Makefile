TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := crc8_parallel
COCOTB_TEST_MODULES := test_crc8_parallel

VHDL_SOURCES := $(PWD)/../../rtl/crc8_parallel.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=crc8_parallel.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
