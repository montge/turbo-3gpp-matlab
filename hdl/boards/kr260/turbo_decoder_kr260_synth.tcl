# =============================================================================
# turbo_decoder_kr260_synth.tcl
# -----------------------------------------------------------------------------
# Reproducible TCL build script for the KR260 (Kria K26) decoder demo - the
# Xilinx analog of the DE2 .qsf flow. See openspec/changes/add-fpga-kr260-
# decoder-port/ for the plan. The committed artifact is THIS TCL (not the
# binary .xpr) so the build is reviewable / reproducible.
#
# Stages of the openspec plan covered by this script (selectable via -mode):
#
#   -mode synth_ooc   (DEFAULT, stage 1.2/1.3)
#       Out-of-context synthesis of `turbo_decoder_top` ONLY -- no board
#       wrapper, no clocking IP, no .xdc. Proves the cores port to Xilinx
#       (generic --std=08 VHDL, no Altera primitives) and produces a synth
#       report we can mine for BRAM inference (Altera ramstyle="M4K" attrs are
#       inert here -- expect RAMB36/18 inference on the loop memories;
#       design.md §7).
#
#   -mode bd_only     (stage 2.1 sanity)
#       Create the Zynq MPSoC clocking BD ONLY -- no synth, no impl. Used to
#       validate the BD parameterization (validate_bd_design returns no
#       errors) without paying the bitstream-build cost. Writes the BD into a
#       temporary project under $BUILD_DIR/bd_check/. Re-runnable: deletes any
#       prior project at that path.
#
#   -mode bitstream   (stage 3+4 full demo build -- parent drives this)
#       Full demo synth + impl + write_bitstream. Creates a real project (BD
#       needs a real project, not in_memory), reads the KR260 wrapper +
#       golden ROM + cores, runs the BD generator, adds the .xdc, and runs
#       synth_1 + impl_1 -to write_bitstream. Logs utilization + timing into
#       $BUILD_DIR. Long-running (>10 min) -- do not invoke from a sub-agent;
#       parent drives.
#
# Recurrence-pipelining levers (the merged DE2 result):
#   The K26 fabric is far faster than the DE2 Cyclone II, so we enable all
#   three levers (ANCHOR_NORM + BAL_TREE_FOLD + PIPE_DFOLD) by default for the
#   demo, just like the DE2 25 MHz build. The cores stay UNMODIFIED -- only the
#   generics flip (set at the wrapper's component map, not via TCL override).
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
set DE2_DIR    [file join $REPO_ROOT hdl boards de2]
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

# Board-wrapper-extra sources for the full demo (stage 3): the on-chip golden
# ROM (REUSED unchanged from the DE2 build -- same K=512, max_iter=2 row) and
# the KR260 wrapper itself.
set DEMO_EXTRA_SOURCES [list \
    [file join $DE2_DIR  turbo_decoder_golden_pkg.vhdl] \
    [file join $SCRIPT_DIR turbo_decoder_kr260_top.vhdl] \
]
set DEMO_XDC [file join $SCRIPT_DIR turbo_decoder_kr260.xdc]

# Sanity-check every source exists before we set up the project (caught a
# stale path early on the DE2 in a prior session).
proc check_files {flist} {
    foreach f $flist {
        if {![file exists $f]} {
            error "missing source: $f"
        }
    }
}
check_files $CORE_SOURCES

# =============================================================================
# kr260_create_clocking_bd : create the minimal Zynq MPSoC PS clocking BD.
# -----------------------------------------------------------------------------
# Produces a BD with:
#   * zynq_ultra_ps_e_0   K26 board preset applied; AXI masters/slaves all
#                         disabled (we only need the PL clock); PL_CLK0
#                         enabled at 100 MHz.
#   * proc_sys_reset_0    synchronizes the BD's peripheral reset off pl_clk0
#                         from the PS's pl_resetn0.
# Exposes TWO output ports on the BD: pl_clk0 (the 100 MHz clock to the PL)
# and pl_resetn0 (the synchronized active-LOW reset from proc_sys_reset).
#
# After save_bd_design, `make_wrapper ... -import` creates and imports
# `<bd_name>_wrapper.vhd` -- which is the component our turbo_decoder_kr260_top
# wrapper instantiates.
#
# Parameterized + idempotent: deletes any pre-existing BD of the same name in
# the current project so re-runs are safe.
#
# Returns the wrapper module name (`<bd_name>_wrapper`).
# =============================================================================
proc kr260_create_clocking_bd { bd_name part board_part } {
    puts "    -> creating BD: $bd_name (PS pl_clk0 = 100 MHz, no AXI)"

    # If a BD by this name already exists in the project, remove it first so
    # the proc is re-runnable.
    if {[llength [get_files -quiet ${bd_name}.bd]] > 0} {
        puts "       (removing existing BD $bd_name.bd)"
        export_ip_user_files -of_objects [get_files ${bd_name}.bd] \
            -no_script -reset -force -quiet
        remove_files [get_files ${bd_name}.bd]
    }

    create_bd_design $bd_name
    current_bd_design $bd_name

    # 1. Zynq MPSoC PS. Use wildcard version so the script survives Vivado
    #    point releases (the IP minor version bumps between 2024.x / 2025.x).
    set ps_vlnv [lindex [get_ipdefs xilinx.com:ip:zynq_ultra_ps_e:*] end]
    if {$ps_vlnv eq ""} {
        error "could not find zynq_ultra_ps_e IP -- check Vivado install"
    }
    puts "       using PS IP: $ps_vlnv"
    create_bd_cell -type ip -vlnv $ps_vlnv zynq_ultra_ps_e_0

    # 2. Apply the K26 board preset (boards file must be installed; verified
    #    via $board_part). Disable any AXI masters/slaves the preset enables.
    apply_bd_automation \
        -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
        -config [list apply_board_preset {1} Master Disable Slave Disable] \
        [get_bd_cells zynq_ultra_ps_e_0]

    # 3. Configure: no AXI master/slave ports, PL_CLK0 on at 100 MHz.
    set_property -dict [list \
        CONFIG.PSU__USE__M_AXI_GP0 {0} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__USE__S_AXI_GP0 {0} \
        CONFIG.PSU__USE__S_AXI_GP1 {0} \
        CONFIG.PSU__USE__S_AXI_GP2 {0} \
        CONFIG.PSU__USE__S_AXI_GP3 {0} \
        CONFIG.PSU__USE__S_AXI_GP4 {0} \
        CONFIG.PSU__USE__S_AXI_GP5 {0} \
        CONFIG.PSU__USE__S_AXI_GP6 {0} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    ] [get_bd_cells zynq_ultra_ps_e_0]

    # 4. proc_sys_reset for the PL clock domain.
    set rst_vlnv [lindex [get_ipdefs xilinx.com:ip:proc_sys_reset:*] end]
    if {$rst_vlnv eq ""} {
        error "could not find proc_sys_reset IP"
    }
    create_bd_cell -type ip -vlnv $rst_vlnv proc_sys_reset_0

    connect_bd_net \
        [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
        [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
    connect_bd_net \
        [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
        [get_bd_pins proc_sys_reset_0/ext_reset_in]

    # 5. BD output ports for the wrapper. pl_clk0 comes from the PS directly;
    #    pl_resetn0 comes from proc_sys_reset's peripheral_aresetn (the
    #    synchronized active-low reset) -- using this rather than the raw PS
    #    reset gives the wrapper a clean, clk-synchronous reset edge.
    create_bd_port -dir O -type clk pl_clk0
    create_bd_port -dir O -type rst pl_resetn0

    connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_ports pl_clk0]
    connect_bd_net \
        [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
        [get_bd_ports pl_resetn0]

    # 6. Validate + save + wrap.
    validate_bd_design
    save_bd_design

    set bd_file [get_files ${bd_name}.bd]
    make_wrapper -files $bd_file -top -import -force

    return "${bd_name}_wrapper"
}

# ---- mode dispatch ----------------------------------------------------------
switch -- $MODE {
    synth_ooc {
        # In-memory project for OOC synth -- BDs not needed here.
        create_project -in_memory -part $PART
        set_property board_part $BOARD_PART [current_project]
        set_property target_language VHDL   [current_project]
        foreach f $CORE_SOURCES {
            read_vhdl $f
            set_property FILE_TYPE {VHDL 2008} [get_files $f]
            puts "    added: $f"
        }

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
    bd_only {
        # Sanity-check the BD parameterization without paying a synth cost.
        # Creates a real (on-disk) project because BDs cannot live in an
        # in_memory project. Re-runnable: clobbers any prior project at the
        # same path.
        check_files $DEMO_EXTRA_SOURCES

        set PROJ_DIR [file join $BUILD_DIR bd_check]
        if {[file exists $PROJ_DIR]} {
            puts "    (removing existing project dir: $PROJ_DIR)"
            file delete -force $PROJ_DIR
        }
        file mkdir $PROJ_DIR

        create_project -force kr260_bd_check $PROJ_DIR -part $PART
        set_property board_part $BOARD_PART [current_project]
        set_property target_language VHDL   [current_project]

        # We don't actually NEED the cores for a BD-only check, but adding
        # them exercises the same project-setup path the bitstream mode
        # uses -- catches issues earlier.
        foreach f $CORE_SOURCES {
            read_vhdl $f
            set_property FILE_TYPE {VHDL 2008} [get_files $f]
        }
        foreach f $DEMO_EXTRA_SOURCES {
            read_vhdl $f
            set_property FILE_TYPE {VHDL 2008} [get_files $f]
        }

        # Run the proc; if validate_bd_design hits an error it will throw
        # and the Vivado batch run will return non-zero.
        set wrapper_name [kr260_create_clocking_bd kr260_clocking $PART $BOARD_PART]
        puts ""
        puts "=== BD created: kr260_clocking ==="
        puts "    wrapper module name: $wrapper_name"
        puts "    validate_bd_design returned with no errors."
        puts "=== bd_only mode done ==="
    }
    bitstream {
        # Full synth + impl + write_bitstream. Long-running -- parent drives.
        check_files $DEMO_EXTRA_SOURCES
        if {![file exists $DEMO_XDC]} {
            error "missing constraints: $DEMO_XDC"
        }

        set PROJ_DIR [file join $BUILD_DIR proj]
        if {[file exists $PROJ_DIR]} {
            puts "    (removing existing project dir: $PROJ_DIR)"
            file delete -force $PROJ_DIR
        }
        file mkdir $PROJ_DIR

        create_project -force kr260_demo $PROJ_DIR -part $PART
        set_property board_part $BOARD_PART [current_project]
        set_property target_language VHDL   [current_project]

        # Core + demo sources.
        foreach f $CORE_SOURCES {
            read_vhdl $f
            set_property FILE_TYPE {VHDL 2008} [get_files $f]
            puts "    added: $f"
        }
        foreach f $DEMO_EXTRA_SOURCES {
            read_vhdl $f
            set_property FILE_TYPE {VHDL 2008} [get_files $f]
            puts "    added: $f"
        }

        # Clocking BD -- adds the wrapper VHDL to the project via -import.
        set wrapper_name [kr260_create_clocking_bd kr260_clocking $PART $BOARD_PART]
        puts "    BD wrapper added: $wrapper_name"

        # Constraints.
        add_files -fileset constrs_1 $DEMO_XDC
        puts "    added xdc: $DEMO_XDC"

        # Top-level + compile order.
        set_property top turbo_decoder_kr260_top [current_fileset]
        update_compile_order -fileset sources_1

        # Synth + impl + bitstream.
        puts ""
        puts "=== launching synth_1 ==="
        launch_runs synth_1 -jobs 8
        wait_on_run synth_1
        if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
            error "synth_1 did not complete cleanly: [get_property STATUS [get_runs synth_1]]"
        }

        puts ""
        puts "=== launching impl_1 -to_step write_bitstream ==="
        launch_runs impl_1 -to_step write_bitstream -jobs 8
        wait_on_run impl_1
        set impl_status [get_property STATUS [get_runs impl_1]]
        if {![string match "*write_bitstream Complete*" $impl_status] \
            && ![string match "*Complete!*" $impl_status]} {
            error "impl_1 did not complete cleanly: $impl_status"
        }

        # Reports + bitstream location.
        open_run impl_1
        report_utilization      -file [file join $BUILD_DIR demo_utilization.rpt]
        report_timing_summary   -file [file join $BUILD_DIR demo_timing_summary.rpt]
        set bit_glob [glob -nocomplain [file join $PROJ_DIR kr260_demo.runs impl_1 *.bit]]
        puts ""
        puts "=== bitstream mode done ==="
        puts "    .bit : $bit_glob"
        puts "    utilization : [file join $BUILD_DIR demo_utilization.rpt]"
        puts "    timing      : [file join $BUILD_DIR demo_timing_summary.rpt]"
    }
    default {
        error "unknown mode: $MODE (expected synth_ooc | bd_only | bitstream)"
    }
}
