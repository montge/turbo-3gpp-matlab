library ieee;
use ieee.std_logic_1164.all;

-- On-chip golden-vector ROM for the DE2 tx_chain_top demo.
--
-- PROVENANCE: this is the K=40 row of hdl/vectors/tx_chain.csv (the smallest
-- committed tx_chain vector), copied verbatim:
--
--   K,N_ref,I_LBRM,rv,E,c,e
--   40,0,0,0,400,
--     c = 1101010001011000011111111011101110101111            (40 bits)
--     e = 1010111000110110110000111110010011011101...         (400 bits)
--
-- That same row is the bit-exact golden the tx_chain_top cocotb lane checks
-- (hdl/sim/tx_chain_top/, vector hdl/vectors/tx_chain.csv). This package is
-- board-presentation data only: it lives under hdl/boards/, NOT under
-- hdl/rtl/, and the hardened RTL core is unaware of it.
--
-- Bit ordering: index 0 is the FIRST streamed/emitted bit (MSB-first as
-- written in the CSV), matching the cocotb driver which streams c[0], c[1], ...
-- and expects e[0], e[1], ... in that order.
package tx_chain_golden_pkg is
  -- Parameters for the chosen row.
  constant GV_K      : integer := 40;
  constant GV_N_REF  : integer := 0;
  constant GV_I_LBRM : std_logic := '0';
  constant GV_RV     : integer := 0;
  constant GV_E      : integer := 400;

  -- Input code block c (GV_K bits) and expected rate-matched output e (GV_E
  -- bits). index 0 = first bit.
  constant GV_C : std_logic_vector(0 to GV_K-1) :=
    "1101010001011000011111111011101110101111";

  constant GV_E_BITS : std_logic_vector(0 to GV_E-1) :=
    "1010111000110110110000111110010011011101" &
    "1100101000011111001100000011011100110010" &
    "1111101011010001100100010001011110100100" &
    "0100100110111010111000110110110000111110" &
    "0100110111011100101000011111001100000011" &
    "0111001100101111101011010001100100010001" &
    "0111101001000100100110111010111000110110" &
    "1100001111100100110111011100101000011111" &
    "0011000000110111001100101111101011010001" &
    "1001000100010111101001000100100110111010";
end package tx_chain_golden_pkg;
