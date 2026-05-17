library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Circular buffer, TS36.212 SS5.1.4.1.2. Bit-for-bit equivalent of
-- circular_buffer.m. Given the 3 x K_Pi sub-block-interleaved matrix v
-- (each element a bit + filler flag) and (N_ref, I_LBRM, rv_idx, E), builds
-- w (K_w = 3*K_Pi: row1, then rows 2/3 interleaved), computes N_cb and the
-- start offset k_0, and streams E non-filler bits read circularly from w.
--
-- v1 is sim-first: integer arithmetic (incl. ceil/mod) is used directly
-- (GHDL exact). A divider-free synthesis reformulation and the full
-- rate_matching integration are documented follow-ons.
entity circular_buffer is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    start    : in  std_logic;                       -- latch params, begin
    k_pi_in  : in  std_logic_vector(13 downto 0);   -- K_Pi (mult of 32)
    n_ref_in : in  std_logic_vector(15 downto 0);
    i_lbrm   : in  std_logic;
    rv_in    : in  std_logic_vector(1 downto 0);
    e_in     : in  std_logic_vector(15 downto 0);   -- output length E
    v_valid  : in  std_logic;                       -- a v column this cycle
    v1_bit   : in  std_logic;  v1_fill : in std_logic;
    v2_bit   : in  std_logic;  v2_fill : in std_logic;
    v3_bit   : in  std_logic;  v3_fill : in std_logic;
    out_valid: out std_logic;                        -- e_bit valid this cycle
    e_bit    : out std_logic;
    last     : out std_logic
  );
end entity circular_buffer;

architecture rtl of circular_buffer is
  constant KW_MAX : integer := 3 * 6176;             -- 18528

  type bit_arr is array (0 to KW_MAX-1) of std_logic;
  signal w_bit  : bit_arr := (others => '0');
  signal w_fill : bit_arr := (others => '0');

  type state_t is (S_IDLE, S_LOAD, S_COMPUTE, S_READ, S_DONE);
  signal st : state_t := S_IDLE;

  signal K_Pi  : integer range 0 to 6176 := 0;
  signal K_w   : integer range 0 to KW_MAX := 0;
  signal R_TC  : integer range 0 to 193 := 0;
  signal N_cb  : integer range 0 to KW_MAX := 0;
  signal k0    : integer := 0;
  signal Ev    : integer range 0 to 65535 := 0;
  signal NrefR : integer range 0 to 65535 := 0;
  signal RvR   : integer range 0 to 3 := 0;
  signal LbrmR : std_logic := '0';
  signal cidx  : integer range 0 to 6176 := 0;       -- v column counter
  signal jj    : integer := 0;
  signal kk    : integer range 0 to 65535 := 0;

  signal ov, eb, lst : std_logic := '0';
begin
  out_valid <= ov;
  e_bit     <= eb;
  last      <= lst;

  process (clk)
    variable rtc, kw, ncb, q, nref, ev_v : integer;
    variable pos : integer;
  begin
    if rising_edge(clk) then
      ov  <= '0';
      lst <= '0';

      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if start = '1' then
              K_Pi  <= to_integer(unsigned(k_pi_in));
              Ev    <= to_integer(unsigned(e_in));
              NrefR <= to_integer(unsigned(n_ref_in));
              RvR   <= to_integer(unsigned(rv_in));
              LbrmR <= i_lbrm;
              cidx  <= 0;
              st    <= S_LOAD;
            end if;

          when S_LOAD =>
            if v_valid = '1' then
              w_bit(cidx)              <= v1_bit;
              w_fill(cidx)             <= v1_fill;
              w_bit(K_Pi + 2*cidx)     <= v2_bit;
              w_fill(K_Pi + 2*cidx)    <= v2_fill;
              w_bit(K_Pi + 2*cidx + 1) <= v3_bit;
              w_fill(K_Pi + 2*cidx + 1)<= v3_fill;
              if cidx = K_Pi - 1 then
                st <= S_COMPUTE;
              else
                cidx <= cidx + 1;
              end if;
            end if;

          when S_COMPUTE =>
            rtc := K_Pi / 32;
            kw  := 3 * K_Pi;
            if LbrmR = '0' then
              ncb := kw;
            elsif NrefR < kw then
              ncb := NrefR;
            else
              ncb := kw;
            end if;
            -- q = ceil(N_cb / (8*R_TC))
            q := (ncb + 8*rtc - 1) / (8*rtc);
            R_TC <= rtc;
            K_w  <= kw;
            N_cb <= ncb;
            k0   <= rtc * (2*q*RvR + 2);
            jj   <= 0;
            kk   <= 0;
            st   <= S_READ;

          when S_READ =>
            if jj > 8*KW_MAX then
              st <= S_DONE;            -- safety cap (should never hit)
            else
              pos := (k0 + jj) mod N_cb;
              jj <= jj + 1;
              if w_fill(pos) = '0' then
                eb <= w_bit(pos);
                ov <= '1';
                if kk = Ev - 1 then
                  lst <= '1';
                  st  <= S_DONE;
                else
                  kk <= kk + 1;
                end if;
              end if;
            end if;

          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
