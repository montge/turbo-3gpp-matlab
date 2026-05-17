library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qpp_rom_pkg.all;

-- Complete hardware LTE transmit chain: turbo encode -> rate matching.
-- Given a code block c, its length K and rate-match params, produces the
-- length-E rate-matched bits, bit-for-bit equal to
--   rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)),
--                  N_ref, I_LBRM, rv_idx, E).
--
-- Wires the UNMODIFIED turbo_encode_top (its K+4 column stream) directly into
-- the UNMODIFIED rate_matching_top (D = K+4). Only the start-pulse FSM and
-- pass-through are new.
entity tx_chain_top is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    in_start   : in  std_logic;                       -- latch K/params, begin
    k_in       : in  std_logic_vector(QPP_W-1 downto 0);
    n_ref_in   : in  std_logic_vector(15 downto 0);
    i_lbrm     : in  std_logic;
    rv_in      : in  std_logic_vector(1 downto 0);
    e_in       : in  std_logic_vector(15 downto 0);
    c_in       : in  std_logic;                       -- code bit (LOAD)
    c_in_valid : in  std_logic;
    out_valid  : out std_logic;
    e_bit      : out std_logic;
    last       : out std_logic
  );
end entity tx_chain_top;

architecture rtl of tx_chain_top is
  component turbo_encode_top is
    port (
      clk : in std_logic; rst : in std_logic;
      in_start : in std_logic;
      k_in : in std_logic_vector(QPP_W-1 downto 0);
      c_in : in std_logic; c_in_valid : in std_logic;
      busy : out std_logic;
      d0_o : out std_logic; d1_o : out std_logic; d2_o : out std_logic;
      out_valid : out std_logic; last_o : out std_logic
    );
  end component;

  component rate_matching_top is
    port (
      clk : in std_logic; rst : in std_logic;
      in_start : in std_logic;
      d_len : in std_logic_vector(12 downto 0);
      n_ref_in : in std_logic_vector(15 downto 0);
      i_lbrm : in std_logic;
      rv_in : in std_logic_vector(1 downto 0);
      e_in : in std_logic_vector(15 downto 0);
      d_valid : in std_logic;
      d1_in : in std_logic; d2_in : in std_logic; d3_in : in std_logic;
      out_valid : out std_logic; e_bit : out std_logic; last : out std_logic
    );
  end component;

  type state_t is (S_IDLE, S_START, S_RUN, S_DONE);
  signal st : state_t := S_IDLE;

  signal Kr : unsigned(QPP_W-1 downto 0) := (others => '0');

  signal te_start, te_d0, te_d1, te_d2, te_ov, te_lst, te_busy : std_logic;
  signal rm_start, rm_ov, rm_eb, rm_lst : std_logic;
  signal d_len_s : std_logic_vector(12 downto 0);
begin
  d_len_s <= std_logic_vector(resize(Kr + 4, 13));   -- D = K + 4

  i_te : turbo_encode_top
    port map (clk => clk, rst => rst, in_start => te_start, k_in => k_in,
              c_in => c_in, c_in_valid => c_in_valid, busy => te_busy,
              d0_o => te_d0, d1_o => te_d1, d2_o => te_d2,
              out_valid => te_ov, last_o => te_lst);

  i_rm : rate_matching_top
    port map (clk => clk, rst => rst, in_start => rm_start,
              d_len => d_len_s, n_ref_in => n_ref_in, i_lbrm => i_lbrm,
              rv_in => rv_in, e_in => e_in,
              d_valid => te_ov,                 -- te column stream -> rm load
              d1_in => te_d0, d2_in => te_d1, d3_in => te_d2,
              out_valid => rm_ov, e_bit => rm_eb, last => rm_lst);

  te_start <= '1' when st = S_START else '0';
  rm_start <= '1' when st = S_START else '0';

  out_valid <= rm_ov when (st = S_RUN) else '0';
  e_bit     <= rm_eb;
  last      <= rm_lst when (st = S_RUN) else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              Kr <= unsigned(k_in);
              st <= S_START;
            end if;
          when S_START =>
            st <= S_RUN;             -- te_start + rm_start pulsed
          when S_RUN =>
            if rm_lst = '1' then
              st <= S_DONE;
            end if;
          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
