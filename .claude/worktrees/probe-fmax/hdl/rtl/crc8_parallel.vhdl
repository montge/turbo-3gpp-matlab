library ieee;
use ieee.std_logic_1164.all;

entity crc8_parallel is
  port (
    data_i : in  std_logic_vector(15 downto 0);
    crc_o  : out std_logic_vector(7 downto 0)
  );
end entity crc8_parallel;

architecture rtl of crc8_parallel is
  type generator_matrix_t is array (0 to 15) of std_logic_vector(7 downto 0);

  -- Rows match get_crc_generator_matrix(16, get_3gpp_crc_polynomial('CRC8')).
  constant CRC8_GENERATOR : generator_matrix_t := (
    0  => "00101111",
    1  => "11011010",
    2  => "01101101",
    3  => "11111011",
    4  => "10110000",
    5  => "01011000",
    6  => "00101100",
    7  => "00010110",
    8  => "00001011",
    9  => "11001000",
    10 => "01100100",
    11 => "00110010",
    12 => "00011001",
    13 => "11000001",
    14 => "10101101",
    15 => "10011011"
  );
begin
  process (data_i)
    variable crc_v : std_logic_vector(7 downto 0);
  begin
    crc_v := (others => '0');

    for bit_idx in 0 to 15 loop
      if data_i(15 - bit_idx) = '1' then
        crc_v := crc_v xor CRC8_GENERATOR(bit_idx);
      end if;
    end loop;

    crc_o <= crc_v;
  end process;
end architecture rtl;

