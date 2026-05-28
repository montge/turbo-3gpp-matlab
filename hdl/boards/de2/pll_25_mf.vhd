-- megafunction wizard: %ALTPLL%
-- GENERATION: STANDARD
-- VERSION: WM1.0
-- MODULE: altpll

-- ============================================================
-- File Name: pll_25_mf.vhd
-- Megafunction Name(s):
-- 			altpll
--
-- Simulation Library Files(s):
--
-- ============================================================
-- ************************************************************
-- WIZARD-GENERATED altpll, hand-adapted from pll_12p5_mf.vhd for the
-- add-fpga-decoder-recurrence-pipelining 25 MHz board build: the ONLY
-- functional change is clk0_divide_by 4 -> 2 (50 MHz / 2 = 25.000000 MHz,
-- 40 ns period) and the CBX module prefix / entity name 12p5 -> 25. All other
-- altpll parameters are byte-identical to the validated 13.0sp1 wizard output.
-- The decoder closes timing at 25 MHz (restricted Fmax 27.63 MHz with the
-- recurrence-pipelining levers enabled), so divide-by-2 is the next
-- integer-friendly ratio above the prior divide-by-4 (12.5 MHz) workaround.
-- ************************************************************


--Copyright (C) 1991-2013 Altera Corporation
--Your use of Altera Corporation's design tools, logic functions
--and other software and tools, and its AMPP partner logic
--functions, and any output files from any of the foregoing
--(including device programming or simulation files), and any
--associated documentation or information are expressly subject
--to the terms and conditions of the Altera Program License
--Subscription Agreement, Altera MegaCore Function License
--Agreement, or other applicable license agreement, including,
--without limitation, that your use is for the sole purpose of
--programming logic devices manufactured by Altera and sold by
--Altera or its authorized distributors.  Please refer to the
--applicable agreement for further details.


LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.all;

ENTITY pll_25_mf IS
	PORT
	(
		areset		: IN STD_LOGIC  := '0';
		inclk0		: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC ;
		locked		: OUT STD_LOGIC
	);
END pll_25_mf;


ARCHITECTURE SYN OF pll_25_mf IS

	SIGNAL sub_wire0	: STD_LOGIC ;
	SIGNAL sub_wire1	: STD_LOGIC_VECTOR (5 DOWNTO 0);
	SIGNAL sub_wire2	: STD_LOGIC ;
	SIGNAL sub_wire3	: STD_LOGIC ;
	SIGNAL sub_wire4	: STD_LOGIC_VECTOR (1 DOWNTO 0);
	SIGNAL sub_wire5_bv	: BIT_VECTOR (0 DOWNTO 0);
	SIGNAL sub_wire5	: STD_LOGIC_VECTOR (0 DOWNTO 0);



	COMPONENT altpll
	GENERIC (
		clk0_divide_by		: NATURAL;
		clk0_duty_cycle		: NATURAL;
		clk0_multiply_by		: NATURAL;
		clk0_phase_shift		: STRING;
		compensate_clock		: STRING;
		gate_lock_signal		: STRING;
		inclk0_input_frequency		: NATURAL;
		intended_device_family		: STRING;
		invalid_lock_multiplier		: NATURAL;
		lpm_hint		: STRING;
		lpm_type		: STRING;
		operation_mode		: STRING;
		port_activeclock		: STRING;
		port_areset		: STRING;
		port_clkbad0		: STRING;
		port_clkbad1		: STRING;
		port_clkloss		: STRING;
		port_clkswitch		: STRING;
		port_configupdate		: STRING;
		port_fbin		: STRING;
		port_inclk0		: STRING;
		port_inclk1		: STRING;
		port_locked		: STRING;
		port_pfdena		: STRING;
		port_phasecounterselect		: STRING;
		port_phasedone		: STRING;
		port_phasestep		: STRING;
		port_phaseupdown		: STRING;
		port_pllena		: STRING;
		port_scanaclr		: STRING;
		port_scanclk		: STRING;
		port_scanclkena		: STRING;
		port_scandata		: STRING;
		port_scandataout		: STRING;
		port_scandone		: STRING;
		port_scanread		: STRING;
		port_scanwrite		: STRING;
		port_clk0		: STRING;
		port_clk1		: STRING;
		port_clk2		: STRING;
		port_clk3		: STRING;
		port_clk4		: STRING;
		port_clk5		: STRING;
		port_clkena0		: STRING;
		port_clkena1		: STRING;
		port_clkena2		: STRING;
		port_clkena3		: STRING;
		port_clkena4		: STRING;
		port_clkena5		: STRING;
		port_extclk0		: STRING;
		port_extclk1		: STRING;
		port_extclk2		: STRING;
		port_extclk3		: STRING;
		valid_lock_multiplier		: NATURAL
	);
	PORT (
			areset	: IN STD_LOGIC ;
			clk	: OUT STD_LOGIC_VECTOR (5 DOWNTO 0);
			inclk	: IN STD_LOGIC_VECTOR (1 DOWNTO 0);
			locked	: OUT STD_LOGIC
	);
	END COMPONENT;

BEGIN
	sub_wire5_bv(0 DOWNTO 0) <= "0";
	sub_wire5    <= To_stdlogicvector(sub_wire5_bv);
	locked    <= sub_wire0;
	sub_wire2    <= sub_wire1(0);
	c0    <= sub_wire2;
	sub_wire3    <= inclk0;
	sub_wire4    <= sub_wire5(0 DOWNTO 0) & sub_wire3;

	altpll_component : altpll
	GENERIC MAP (
		clk0_divide_by => 2,
		clk0_duty_cycle => 50,
		clk0_multiply_by => 1,
		clk0_phase_shift => "0",
		compensate_clock => "CLK0",
		gate_lock_signal => "NO",
		inclk0_input_frequency => 20000,
		intended_device_family => "Cyclone II",
		invalid_lock_multiplier => 5,
		lpm_hint => "CBX_MODULE_PREFIX=pll_25_mf",
		lpm_type => "altpll",
		operation_mode => "NORMAL",
		port_activeclock => "PORT_UNUSED",
		port_areset => "PORT_USED",
		port_clkbad0 => "PORT_UNUSED",
		port_clkbad1 => "PORT_UNUSED",
		port_clkloss => "PORT_UNUSED",
		port_clkswitch => "PORT_UNUSED",
		port_configupdate => "PORT_UNUSED",
		port_fbin => "PORT_UNUSED",
		port_inclk0 => "PORT_USED",
		port_inclk1 => "PORT_UNUSED",
		port_locked => "PORT_USED",
		port_pfdena => "PORT_UNUSED",
		port_phasecounterselect => "PORT_UNUSED",
		port_phasedone => "PORT_UNUSED",
		port_phasestep => "PORT_UNUSED",
		port_phaseupdown => "PORT_UNUSED",
		port_pllena => "PORT_UNUSED",
		port_scanaclr => "PORT_UNUSED",
		port_scanclk => "PORT_UNUSED",
		port_scanclkena => "PORT_UNUSED",
		port_scandata => "PORT_UNUSED",
		port_scandataout => "PORT_UNUSED",
		port_scandone => "PORT_UNUSED",
		port_scanread => "PORT_UNUSED",
		port_scanwrite => "PORT_UNUSED",
		port_clk0 => "PORT_USED",
		port_clk1 => "PORT_UNUSED",
		port_clk2 => "PORT_UNUSED",
		port_clk3 => "PORT_UNUSED",
		port_clk4 => "PORT_UNUSED",
		port_clk5 => "PORT_UNUSED",
		port_clkena0 => "PORT_UNUSED",
		port_clkena1 => "PORT_UNUSED",
		port_clkena2 => "PORT_UNUSED",
		port_clkena3 => "PORT_UNUSED",
		port_clkena4 => "PORT_UNUSED",
		port_clkena5 => "PORT_UNUSED",
		port_extclk0 => "PORT_UNUSED",
		port_extclk1 => "PORT_UNUSED",
		port_extclk2 => "PORT_UNUSED",
		port_extclk3 => "PORT_UNUSED",
		valid_lock_multiplier => 1
	)
	PORT MAP (
		areset => areset,
		inclk => sub_wire4,
		locked => sub_wire0,
		clk => sub_wire1
	);



END SYN;
