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
#      zynq_ultra_ps_e PS via the BD, so the clock object should be auto-
#      created by the Vivado IP integrator when the BD is added. We add an
#      EXPLICIT create_clock as a belt-and-suspenders -- in some Vivado
#      versions the PS's pl_clk0 only gets a derived clock from the upstream
#      PSU clock if implementation can see the PSU constraints, so an
#      explicit constraint on the BD wrapper's pl_clk0 output ensures synth
#      and impl both see the constraint regardless of clock-derivation order.
#      If Vivado warns that the explicit clock conflicts with the IP-declared
#      one, comment OUT the create_clock below and rely on the IP definition.
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
if {[llength [get_pins -quiet -hierarchical -filter {NAME =~ */pl_clk0}]] > 0} {
    create_clock -name pl_clk0 -period 10.000 \
        [get_pins -hierarchical -filter {NAME =~ */pl_clk0}]
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
