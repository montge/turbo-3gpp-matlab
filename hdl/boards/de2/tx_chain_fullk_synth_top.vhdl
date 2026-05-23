library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;          -- QPP_W

-- Full-K=6144 synthesis harness for tx_chain_top (add-fpga-block-ram-inference
-- stage 4). This wrapper exists ONLY to make Quartus II 13.0sp1 fit/time the
-- UNMODIFIED tx_chain_top at its DEFAULT generics (MAXK=6144, DMAX=6148,
-- KW_MAX=18528) — i.e. the true TS36.212 maxima — on the EP2C35F672C6.
--
-- It is NOT a board demo and has no golden self-check; the K=40 demo
-- (tx_chain_de2_top) keeps that role. The point here is the SYNTHESIS ORACLE:
-- prove the three M4K-inference fixes (#45/#46/#47) make the full-size buffers
-- infer M4K so the chain fits and closes 50 MHz.
--
-- To stop the fitter from pruning the wide datapath (which would understate the
-- resource cost and hide the buffers), every scalar core input is fed from a
-- register chain seeded by a single pin, and every core output is folded into a
-- single registered pin. Nothing is a compile-time constant, so the full-depth
-- buffers and full-width control are preserved.
--
-- I/O (minimal, just enough to anchor the datapath to real pins):
--   CLOCK_50  50 MHz functional clock (the only clock; whole design is on it)
--   KEY[0]    active-low seed/stimulus input (synchronized; drives the chain)
--   LEDG[0]   registered fold of all core outputs (anchors the output cone)
entity tx_chain_fullk_synth_top is
  port (
    CLOCK_50 : in  std_logic;
    KEY      : in  std_logic_vector(0 downto 0);
    LEDG     : out std_logic_vector(0 downto 0)
  );
end entity tx_chain_fullk_synth_top;

architecture rtl of tx_chain_fullk_synth_top is
  component tx_chain_top is
    generic (
      MAXK   : integer := 6144;
      DMAX   : integer := 6148;
      KW_MAX : integer := 3 * 6176
    );
    port (
      clk        : in  std_logic;
      rst        : in  std_logic;
      in_start   : in  std_logic;
      k_in       : in  std_logic_vector(QPP_W-1 downto 0);
      n_ref_in   : in  std_logic_vector(15 downto 0);
      i_lbrm     : in  std_logic;
      rv_in      : in  std_logic_vector(1 downto 0);
      e_in       : in  std_logic_vector(15 downto 0);
      c_in       : in  std_logic;
      c_in_valid : in  std_logic;
      out_valid  : out std_logic;
      e_bit      : out std_logic;
      last       : out std_logic
    );
  end component;

  -- A 50-bit LFSR-ish seed register fans out into every core input so none of
  -- them is constant. Seeded by the (synchronized) KEY[0] stimulus pin.
  signal seed : std_logic_vector(49 downto 0) := (others => '0');
  signal key_s : std_logic_vector(1 downto 0) := (others => '1');

  signal core_rst    : std_logic;
  signal core_start  : std_logic;
  signal core_kin    : std_logic_vector(QPP_W-1 downto 0);
  signal core_nref   : std_logic_vector(15 downto 0);
  signal core_ilbrm  : std_logic;
  signal core_rv     : std_logic_vector(1 downto 0);
  signal core_ein    : std_logic_vector(15 downto 0);
  signal core_cin    : std_logic;
  signal core_cinv   : std_logic;

  signal core_ov   : std_logic;
  signal core_eb   : std_logic;
  signal core_last : std_logic;

  signal out_fold : std_logic := '0';
begin
  ---------------------------------------------------------------------------
  -- Stimulus seed register: a simple maximal-tap feedback chain folded with
  -- the synchronized KEY[0] input so it is non-constant and not optimizable.
  ---------------------------------------------------------------------------
  process (CLOCK_50)
  begin
    if rising_edge(CLOCK_50) then
      key_s <= key_s(0) & KEY(0);
      seed  <= seed(48 downto 0) &
               (seed(49) xor seed(46) xor seed(31) xor seed(0) xor key_s(1));
    end if;
  end process;

  -- Fan the seed bits out into the full-width control/data inputs (registered
  -- by the core's own input regs). Slices overlap intentionally; the only
  -- requirement is that they are not constants.
  core_rst   <= seed(0);
  core_start <= seed(1);
  core_kin   <= seed(QPP_W downto 1);          -- 13 bits
  core_nref  <= seed(16 downto 1);             -- 16 bits
  core_ilbrm <= seed(2);
  core_rv    <= seed(4 downto 3);
  core_ein   <= seed(31 downto 16);            -- 16 bits
  core_cin   <= seed(5);
  core_cinv  <= seed(6);

  ---------------------------------------------------------------------------
  -- The UNMODIFIED full-size core at its DEFAULT generics (the maxima).
  ---------------------------------------------------------------------------
  u_core : tx_chain_top
    port map (
      clk        => CLOCK_50,
      rst        => core_rst,
      in_start   => core_start,
      k_in       => core_kin,
      n_ref_in   => core_nref,
      i_lbrm     => core_ilbrm,
      rv_in      => core_rv,
      e_in       => core_ein,
      c_in       => core_cin,
      c_in_valid => core_cinv,
      out_valid  => core_ov,
      e_bit      => core_eb,
      last       => core_last
    );

  ---------------------------------------------------------------------------
  -- Fold all outputs into one registered pin so the output cone is anchored.
  ---------------------------------------------------------------------------
  process (CLOCK_50)
  begin
    if rising_edge(CLOCK_50) then
      out_fold <= out_fold xor core_ov xor core_eb xor core_last;
    end if;
  end process;

  LEDG(0) <= out_fold;
end architecture rtl;
