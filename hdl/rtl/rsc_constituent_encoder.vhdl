library ieee;
use ieee.std_logic_1164.all;

-- Rate-1 recursive systematic convolutional constituent encoder,
-- TS36.212 SS5.1.3.2.1-5.1.3.2.2: 3 memory elements, generator [1,1,0,1],
-- feedback [1,0,1,1], with the 3-step trellis termination.
--
-- Bit-for-bit equivalent of constituent_encoder.m. Outputs are combinational
-- (Mealy) for the step currently presented; the shift-register state advances
-- on the rising clock edge when `en` is asserted.
--
--   data step (term='0'): s1' = din xor s2 xor s3
--                          x   = din
--                          z   = s1' xor s1 xor s3
--   term step (term='1'): s1' = 0
--                          x   = s2 xor s3
--                          z   = s1' xor s1 xor s3   (= s1 xor s3)
--   next state          : s1<=s1', s2<=s1, s3<=s2
entity rsc_constituent_encoder is
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;  -- synchronous: clears state to 0 (start of block)
    en   : in  std_logic;  -- advance one trellis step on the next rising edge
    term : in  std_logic;  -- '0' = data step (uses din); '1' = termination step
    din  : in  std_logic;  -- code-block bit (data step only)
    x_o  : out std_logic;  -- systematic (data) / termination bit, this step
    z_o  : out std_logic   -- parity bit, this step
  );
end entity rsc_constituent_encoder;

architecture rtl of rsc_constituent_encoder is
  signal s1, s2, s3 : std_logic := '0';
  signal s1_plus    : std_logic;
begin
  s1_plus <= '0' when term = '1' else (din xor s2 xor s3);
  x_o     <= (s2 xor s3) when term = '1' else din;
  z_o     <= s1_plus xor s1 xor s3;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s1 <= '0';
        s2 <= '0';
        s3 <= '0';
      elsif en = '1' then
        s1 <= s1_plus;
        s2 <= s1;
        s3 <= s2;
      end if;
    end if;
  end process;
end architecture rtl;
