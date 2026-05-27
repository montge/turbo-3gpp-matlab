TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := lcd_format_tb_top
COCOTB_TEST_MODULES := test_lcd_format

# The shared LCD digit-format package (hdl/boards/lcd_format_pkg.vhdl) plus a
# thin harness that renders representative values and exposes the ASCII bytes.
# Nothing under hdl/rtl/ is touched by this lane.
VHDL_SOURCES := $(PWD)/../../boards/lcd_format_pkg.vhdl \
                $(PWD)/lcd_format_tb_top.vhdl

EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=lcd_format_tb_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
