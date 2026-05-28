library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- K -> (d0, step) lookup over the generated TS36.212 Table 5.1.3-3 ROM.
-- The 188 supported K are non-uniformly spaced, so a sequential scan
-- (<= QPP_ROM_N cycles, well under the K>=40 encode time) is used. Asserts
-- `supported` for a table K, deasserts it otherwise. `done` is LEVEL-high:
-- it asserts when the scan completes and stays asserted until the next
-- `start` (or `rst`). Consumers latch on the `done='1'` edge and leave the
-- waiting state, so the held level is harmless and intentional (a one-cycle
-- pulse was considered; level is kept to avoid any timing change to the
-- bit-exact-verified turbo_encode_top / tx_chain_top integrators).
entity qpp_rom is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;                          -- latch k_in, begin scan
    k_in      : in  std_logic_vector(QPP_W-1 downto 0);
    done      : out std_logic;
    supported : out std_logic;
    d0_o      : out std_logic_vector(QPP_W-1 downto 0);
    step_o    : out std_logic_vector(QPP_W-1 downto 0)
  );
end entity qpp_rom;

architecture rtl of qpp_rom is
  signal idx      : integer range 0 to QPP_ROM_N-1 := 0;
  signal scanning : std_logic := '0';
  signal kr       : unsigned(QPP_W-1 downto 0) := (others => '0');
  signal sup      : std_logic := '0';
  signal dn       : std_logic := '0';
  signal d0r      : unsigned(QPP_W-1 downto 0) := (others => '0');
  signal stepr    : unsigned(QPP_W-1 downto 0) := (others => '0');
begin
  done      <= dn;
  supported <= sup;
  d0_o      <= std_logic_vector(d0r);
  step_o    <= std_logic_vector(stepr);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        scanning <= '0';
        dn       <= '0';
        sup      <= '0';
      elsif start = '1' then
        kr       <= unsigned(k_in);
        idx      <= 0;
        scanning <= '1';
        dn       <= '0';
        sup      <= '0';
      elsif scanning = '1' then
        if QPP_TABLE(idx).k = kr then
          d0r      <= QPP_TABLE(idx).d0;
          stepr    <= QPP_TABLE(idx).step;
          sup      <= '1';
          dn       <= '1';
          scanning <= '0';
        elsif idx = QPP_ROM_N - 1 then
          sup      <= '0';
          dn       <= '1';
          scanning <= '0';
        else
          idx <= idx + 1;
        end if;
      end if;
    end if;
  end process;
end architecture rtl;
