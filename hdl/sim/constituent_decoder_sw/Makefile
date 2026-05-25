TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := constituent_decoder
COCOTB_TEST_MODULES := test_constituent_decoder_sw

VHDL_SOURCES := $(PWD)/../../rtl/constituent_decoder.vhdl
EXTRA_ARGS += --std=08

# Windowed schedule generics. WINDOW_LEN / ACQ_LEN are ELABORATION-TIME
# generics on constituent_decoder (default WINDOW_LEN = N_MAX => full-block
# superset, exercised by the P1 lane). This lane drives the SLIDING-WINDOW
# path, so it overrides both via GHDL -g (same -g override pattern the P2
# turbo_decoder_top lane uses for MAX_ITERATIONS). The pinned W = 64 / L = 48
# match scripts/generate_hdl_constituent_decoder_sw_vectors.m (the values the
# golden CSV was generated at); changing one without regenerating the CSV
# breaks the bit-exact contract.
WINDOW_LEN ?= 64
ACQ_LEN    ?= 48
SIM_ARGS += -gWINDOW_LEN=$(WINDOW_LEN)
SIM_ARGS += -gACQ_LEN=$(ACQ_LEN)
SIM_ARGS += --vcd=constituent_decoder_sw.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
