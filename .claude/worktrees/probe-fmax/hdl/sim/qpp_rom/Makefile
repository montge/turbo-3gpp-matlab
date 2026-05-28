TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := qpp_rom
COCOTB_TEST_MODULES := test_qpp_rom

VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl
EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=qpp_rom.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
