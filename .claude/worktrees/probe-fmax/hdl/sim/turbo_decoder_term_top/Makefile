TOPLEVEL_LANG ?= vhdl
SIM ?= ghdl

TOPLEVEL := turbo_decoder_term_top
COCOTB_TEST_MODULES := test_turbo_decoder_term_top

# Package + reused sub-cores before the integrating top (GHDL elaboration
# order). turbo_decoder_term_top is the NEW P3 entity (copy-extended from the
# UNMODIFIED P2 turbo_decoder_top) that wraps the UNMODIFIED P1
# constituent_decoder + qpp_rom (+pkg) + qpp_interleaver, and adds the new
# crc24_check core for CRC-aided early termination. The P2 turbo_decoder_top is
# NOT instantiated by the P3 top (the term top is self-contained), so it is not
# compiled here.
VHDL_SOURCES := $(PWD)/../../rtl/qpp_rom_pkg.vhd \
                $(PWD)/../../rtl/qpp_rom.vhdl \
                $(PWD)/../../rtl/qpp_interleaver.vhdl \
                $(PWD)/../../rtl/constituent_decoder.vhdl \
                $(PWD)/../../rtl/crc24_check.vhdl \
                $(PWD)/../../rtl/turbo_decoder_term_top.vhdl
EXTRA_ARGS += --std=08

# MAX_ITERATIONS is an ELABORATION-TIME generic (H = 2*MAX_ITERATIONS half-
# iterations). The golden CSV (hdl/vectors/turbo_decoder_term_top.csv) holds a
# single max_iter value (8); the lane is still structured as the P2 lane's
# per-group sweep so adding a new max_iter row later just extends the group
# list. Each pass overrides -gMAX_ITERATIONS and the cocotb test (via the
# MAX_ITER env var) filters the CSV to the rows whose max_iter matches.
MAX_ITER ?= 8
SIM_ARGS += -gMAX_ITERATIONS=$(MAX_ITER)
SIM_ARGS += --vcd=turbo_decoder_term_top_h$(MAX_ITER).vcd
export MAX_ITER

# Default target: run every distinct max_iter group present in the CSV. Each
# group is a clean sub-make (fresh sim_build) so the elaborated generic and the
# results.xml do not leak between passes.
MAX_ITER_GROUPS := 8

.PHONY: all_groups
all_groups:
	@rc=0; \
	for mi in $(MAX_ITER_GROUPS); do \
	  echo "──────── turbo_decoder_term_top: MAX_ITERATIONS=$$mi ────────"; \
	  rm -rf $(PWD)/sim_build $(PWD)/results.xml; \
	  $(MAKE) -f $(firstword $(MAKEFILE_LIST)) MAX_ITER=$$mi sim || rc=1; \
	done; \
	exit $$rc

include $(shell cocotb-config --makefiles)/Makefile.sim
