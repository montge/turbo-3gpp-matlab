TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := turbo_encoder
COCOTB_TEST_MODULES := test_turbo_encoder

# Component before top so GHDL elaborates the hierarchy.
VHDL_SOURCES := $(PWD)/../../rtl/rsc_constituent_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encoder.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=turbo_encoder.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
