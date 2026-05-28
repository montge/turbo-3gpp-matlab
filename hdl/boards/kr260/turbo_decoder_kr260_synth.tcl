# =============================================================================
# turbo_decoder_kr260_synth.tcl
# -----------------------------------------------------------------------------
# Reproducible TCL build script for the KR260 (Kria K26) decoder demo - the
# Xilinx analog of the DE2 .qsf flow. See openspec/changes/add-fpga-kr260-
# decoder-port/ for the plan. The committed artifact is THIS TCL (not the
# binary .xpr) so the build is reviewable / reproducible.
#
# Stage of the openspec plan covered by this script (selectable via -mode):
#
#   -mode synth_ooc   (DEFAULT, stage 1.2/1.3)
#       Out-of-context synthesis of `turbo_decoder_top` ONLY -- no board
#       wrapper, no clocking IP, no .xdc. Proves the cores port to Xilinx
#       (generic --std=08 VHDL, no Altera primitives) and produces a synth
#       report we can mine for BRAM inference (Altera ramstyle="M4K" attrs are
#       inert here -- expect RAMB36/18 inference on the loop memories;
#       design.md §7).
#
#   -mode synth_demo  (stage 3+ -- TODO, needs the wrapper + clocking + xdc)
#       Full demo top-level synthesis with the KR260 self-check wrapper, the
#       PS pl_clk0 clocking, and the .xdc constraints. Not implemented yet.
#
# Recurrence-pipelining levers (the merged DE2 result):
#   The K26 fabric is far faster than the DE2 Cyclone II, so we enable all
#   three levers (ANCHOR_NORM + BAL_TREE_FOLD + PIPE_DFOLD) by default for the
#   demo, just like the DE2 25 MHz build. The cores stay UNMODIFIED -- only the
#   generics flip.
#
# Usage (PowerShell / bash; vivado MUST be invoked by full path here since the
# install is on D: and not on PATH):
#   "D:/AMDDesignTools/2025.2.1/Vivado/bin/vivado.bat" -mode batch \
#       -source turbo_decoder_kr260_synth.tcl -nojournal -nolog \
#       -tclargs -mode synth_ooc
# =============================================================================

# ---- argument parsing -------------------------------------------------------
set MODE synth_ooc
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {$a eq "-mode"} {
        incr i
        set MODE [lindex $argv $i]
    }
}

# ---- target -----------------------------------------------------------------
# Pinned in openspec/changes/add-fpga-decoder-recurrence-pipelining/design.md
# (the DE2 device-string-gotcha discipline carried over) and confirmed via the
# user's first Vivado GUI project (BoardPart kr260_som:1.1).
set PART       "xck26-sfvc784-2LV-c"
set BOARD_PART "xilinx.com:kr260_som:part0:1.1"
set TOPMOD     turbo_decoder_top

# Path discipline: this script is committed at hdl/boards/kr260/. Cores live at
# hdl/rtl/. Repo root is two dirs up. Outputs land in build/kr260/ (gitignored
# scratch -- never committed). Resolve relative to the script's own location
# so the build works regardless of cwd.
set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize [file join $SCRIPT_DIR ../../..]]
set RTL_DIR    [file join $REPO_ROOT hdl rtl]
set BUILD_DIR  [file join $REPO_ROOT build kr260]
file mkdir $BUILD_DIR

puts ""
puts "=== turbo_decoder_kr260_synth.tcl ==="
puts "    mode       = $MODE"
puts "    PART       = $PART"
puts "    BOARD_PART = $BOARD_PART"
puts "    REPO_ROOT  = $REPO_ROOT"
puts "    BUILD_DIR  = $BUILD_DIR"
puts ""

# ---- shared core sources (the same list the DE2 .qsf carries, minus the
#      Altera-specific PLL/LCD/hex7seg + the board wrapper). These are the
#      generic --std=08 VHDL cores -- the recurrence-pipelined decoder. ----
set CORE_SOURCES [list \
    [file join $RTL_DIR qpp_rom_pkg.vhd] \
    [file join $RTL_DIR qpp_rom.vhdl] \
    [file join $RTL_DIR qpp_interleaver.vhdl] \
    [file join $RTL_DIR constituent_decoder.vhdl] \
    [file join $RTL_DIR turbo_decoder_top.vhdl] \
]

# Sanity-check every source exists before we set up the project (caught a
# stale path early on the DE2 in a prior session).
foreach f $CORE_SOURCES {
    if {![file exists $f]} {
        error "missing source: $f"
    }
}

# ---- in-memory project (no .xpr -- the committed artifact is THIS script) ---
create_project -in_memory -part $PART
set_property board_part $BOARD_PART [current_project]
set_property target_language VHDL   [current_project]

# Read sources as VHDL-2008 (the cores rely on -- std=08 -- the DE2 .qsf used
# VHDL_INPUT_VERSION = VHDL_2008; the Vivado analog is FILE_TYPE = "VHDL 2008"
# applied AFTER read_vhdl). Default read_vhdl is VHDL-93.
foreach f $CORE_SOURCES {
    read_vhdl $f
    set_property FILE_TYPE {VHDL 2008} [get_files $f]
    puts "    added: $f"
}

# ---- mode dispatch ----------------------------------------------------------
switch -- $MODE {
    synth_ooc {
        # Out-of-context synthesis of the decoder core ONLY. Enable all three
        # recurrence-pipelining levers (the DE2 25 MHz result) -- the cores are
        # UNMODIFIED, only the generics flip. -mode out_of_context skips the
        # I/O buffer insertion and any board-level constraint requirements,
        # giving us a clean synth report and utilization for the cores in
        # isolation.
        puts ""
        puts "=== synth_design -top $TOPMOD -mode out_of_context (generics ON) ==="
        synth_design -top $TOPMOD -part $PART -mode out_of_context \
            -generic ANCHOR_NORM=true \
            -generic BAL_TREE_FOLD=true \
            -generic PIPE_DFOLD=true \
            -generic K_MAX=512 \
            -generic MAX_ITERATIONS=2

        # Capture utilization + RAM inference into the build dir for review.
        report_utilization -file [file join $BUILD_DIR ooc_utilization.rpt]
        report_utilization -hierarchical -file [file join $BUILD_DIR ooc_utilization_hier.rpt]
        report_ram_utilization -file [file join $BUILD_DIR ooc_ram_utilization.rpt] -detail
        # Worst-path timing is meaningless in OOC without a constraint, but the
        # *report itself* exposes the critical cone -- mine for the alpha/delta
        # paths to confirm they look like the DE2 ones.
        report_timing_summary -file [file join $BUILD_DIR ooc_timing_summary.rpt]
        puts ""
        puts "=== reports written to $BUILD_DIR ==="
    }
    synth_demo {
        error "synth_demo mode not implemented yet (stage 3+: needs the KR260 self-check wrapper + PS pl_clk0 clocking IP + .xdc)"
    }
    default {
        error "unknown mode: $MODE (expected synth_ooc | synth_demo)"
    }
}
