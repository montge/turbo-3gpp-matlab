TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := rsc_constituent_encoder
COCOTB_TEST_MODULES := test_rsc_constituent_encoder

VHDL_SOURCES := $(PWD)/../../rtl/rsc_constituent_encoder.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=rsc_constituent_encoder.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
