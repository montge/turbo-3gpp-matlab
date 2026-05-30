# =============================================================================
# turbo_decoder_kr260.xdc
# -----------------------------------------------------------------------------
# Physical / timing constraints for the KR260 decoder demo (Kria K26 SOM
# xck26-sfvc784-2LV on the kr260_som carrier). See openspec/changes/add-fpga-
# kr260-decoder-port/design.md §3-§4 for the rationale; this is the Xilinx
# analog of the DE2 demo's .sdc + pin .qsf.
#
# What's pinned here:
#   1. PL clock period (100 MHz / 10 ns). The clock physically comes from the
#      zynq_ultra_ps_e PS via the BD, so the clock object is normally auto-
#      created by the Vivado IP integrator when the BD is added. We add an
#      EXPLICIT create_clock only as a FALLBACK -- guarded so it fires solely
#      when no clock already exists on the pl_clk0 pin. Defining a second clock
#      on the same source pin (when the PS IP already constrained it) triggers
#      a "redefining clock" critical warning and can mis-constrain timing on
#      the one clock the demo is signed off against, so we never do it
#      unconditionally. In Vivado versions where the PSU constraint is absent
#      (no IP-declared clock on pl_clk0) the guard lets our explicit constraint
#      through so synth and impl still see a 10 ns period.
#   2. The two user LEDs (LEDS[0] / LEDS[1]) at the K26 SOM som240_1_d13 /
#      som240_1_d14 pins -- which the kr260_som part0_pins -> kr260_carrier
#      connection_map resolves to FPGA pins F8 / E8 respectively, both
#      LVCMOS18 (the K26 SOM VCCO bank powering these pins is 1.8 V).

# -----------------------------------------------------------------------------
# 1. PL clock from the PS (zynq_ultra_ps_e pl_clk0).
# -----------------------------------------------------------------------------
# The BD's pl_clk0 output net drives `clk` in the top-level via the
# kr260_clocking_wrapper instance. We constrain it on the wrapper output port
# of the BD (Vivado promotes BD wrapper outputs to nets visible in get_pins /
# get_nets at the top level). The conditional `if` guards against the pin not
# existing yet (e.g. during OOC sub-runs where this XDC is read but the BD is
# absent); without the guard, Vivado treats a missing object as a constraint
# error and fails the run.
set pl_clk0_pin [get_pins -quiet -hierarchical -filter {NAME =~ */pl_clk0}]
if {[llength $pl_clk0_pin] > 0} {
    # Only define a clock if the PS IP has NOT already constrained pl_clk0.
    # A second create_clock on the same pin would conflict with the IP clock.
    if {[llength [get_clocks -quiet -of_objects $pl_clk0_pin]] == 0} {
        create_clock -name pl_clk0 -period 10.000 $pl_clk0_pin
    } else {
        puts "INFO: pl_clk0 already constrained by the PS IP; skipping explicit create_clock."
    }
}

# -----------------------------------------------------------------------------
# 2. LED pin assignments (kr260_som part0_pins -> kr260_carrier connection_map).
# -----------------------------------------------------------------------------
#   LEDS[0] = User_led[0]  = som240_1_d13 = FPGA pin F8 (bank 66, VCCO 1.8 V)
#   LEDS[1] = User_led[1]  = som240_1_d14 = FPGA pin E8 (bank 66, VCCO 1.8 V)
# Pin numbers derived from the Vivado board files (xilinx.com:kr260_som:1.1
# and the kr260_carrier board file's connection_map). LVCMOS18 because bank
# 66 on the K26 SOM is fixed at VCCO = 1.8 V by the SOM voltage rail design.
set_property PACKAGE_PIN F8       [get_ports {LEDS[0]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {LEDS[0]}]
set_property PACKAGE_PIN E8       [get_ports {LEDS[1]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {LEDS[1]}]

# -----------------------------------------------------------------------------
# 3. False / async paths.
# -----------------------------------------------------------------------------
# This wrapper has NO async top-level inputs (no KEY/PB on this board for v1;
# the only "async" event is the PS reset deassertion, which proc_sys_reset
# already synchronizes to pl_clk0 before it leaves the BD). So no
# set_false_path constraints are needed.
