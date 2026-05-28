TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := turbo_encode_top
COCOTB_TEST_MODULES := test_turbo_encode_top

# Package + sub-cores before the integrating top (GHDL elaboration order).
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/rsc_constituent_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encoder.vhdl \
                $(PWD)/../../rtl/turbo_encode_top.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=turbo_encode_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
