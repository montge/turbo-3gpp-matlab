TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := constituent_decoder
COCOTB_TEST_MODULES := test_constituent_decoder_logmap

VHDL_SOURCES := $(PWD)/../../rtl/constituent_decoder.vhdl
EXTRA_ARGS += --std=08

# EXACT_LOGMAP is an ELABORATION-TIME boolean generic on constituent_decoder.
# This lane builds the SAME core as hdl/sim/constituent_decoder/ but with the
# exact Log-MAP path enabled (the max* Jacobian correction LUT), then asserts
# bit-exact vs hdl/vectors/constituent_decoder_logmap.csv. GHDL accepts a
# boolean generic override as -g<NAME>=true (same -g mechanism the
# turbo_decoder_top / *_de2 lanes use for integer/index generics).
SIM_ARGS += -gEXACT_LOGMAP=true
SIM_ARGS += --vcd=constituent_decoder_logmap.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
