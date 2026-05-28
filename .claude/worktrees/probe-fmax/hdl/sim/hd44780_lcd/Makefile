TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

# Two fixed-frequency harnesses bake CLK_HZ via generic map (mcode does not
# recompute generic-derived constants on a run-step -g override), so the runner
# selects the clock domain by TOPLEVEL rather than overriding a generic:
#   hd44780_lcd_tb_top  -> 12.5 MHz (default)
#   hd44780_lcd_tb_fast -> 50   MHz
TOPLEVEL ?= hd44780_lcd_tb_top
COCOTB_TEST_MODULES := test_hd44780_lcd

# Shared HD44780 LCD controller (board component, hdl/boards/hd44780_lcd.vhdl)
# plus the thin cocotb test harnesses that fix the two line buffers and expose
# the LCD bus as std_logic ports. Nothing under hdl/rtl/ is touched by this lane.
VHDL_SOURCES := $(PWD)/../../boards/hd44780_lcd.vhdl \
                $(PWD)/hd44780_lcd_tb_top.vhdl

EXTRA_ARGS += --std=08
SIM_ARGS += --vcd=hd44780_lcd_tb_top.vcd

# COCOTB_EXPECT_CLK_HZ tells the test which frequency the selected TOPLEVEL was
# baked at, so it can compute the expected ceil(CLK_HZ*us/1e6) delay counts. The
# default top is the 12.5 MHz harness; test_runner.py also runs the 50 MHz one.
export COCOTB_EXPECT_CLK_HZ ?= 12500000

include $(shell cocotb-config --makefiles)/Makefile.sim
