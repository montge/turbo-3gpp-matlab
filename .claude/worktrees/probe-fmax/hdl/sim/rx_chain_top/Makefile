TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := rx_chain_top
COCOTB_TEST_MODULES := test_rx_chain_top

# Compile every sub-core before the integrating top (GHDL elaboration order).
# rx_chain_top wires the new soft de-rate-match (de_rate_matching_top +
# de_circular_buffer + the UNMODIFIED subblock_interleaver) into the UNMODIFIED
# turbo_decoder_top (which reuses qpp_rom(+pkg) / qpp_interleaver /
# constituent_decoder). Same reuse pattern as tx_chain_top + turbo_decoder_top.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/constituent_decoder.vhdl \
                $(PWD)/../../rtl/turbo_decoder_top.vhdl \
                $(PWD)/../../rtl/subblock_interleaver.vhdl \
                $(PWD)/../../rtl/de_circular_buffer.vhdl \
                $(PWD)/../../rtl/de_rate_matching_top.vhdl \
                $(PWD)/../../rtl/rx_chain_top.vhdl
EXTRA_ARGS += --std=08

# The end-to-end golden CSV (scripts/generate_hdl_rx_chain_vectors.m) decodes at
# the rx_chain_top / turbo_decoder_top MAX_ITERATIONS = 8 default (H = 16), so
# the DUT is elaborated at the same default; no per-frame generic sweep needed
# (single max_iter group, unlike the turbo_decoder_top lane).
SIM_ARGS += --vcd=rx_chain_top.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
