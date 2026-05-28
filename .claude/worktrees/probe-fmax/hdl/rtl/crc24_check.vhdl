library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- crc24_check : streaming GF(2) CRC-24 syndrome check for the P3 turbo
-- decoder's CRC-aided early termination (TS36.212 SS5.1.1 / SS5.1.3.2),
-- part of openspec/changes/add-fpga-turbo-decoder-termination (stage 3).
--
-- ---------------------------------------------------------------------------
-- BIT-EXACT CONTRACT (the ORACLE this core must match):
--   * scripts/fixedpoint_turbo_decoder_term.m -> crc_stop_check() calls
--     calculate_crc_bits(c, G_max) and stops when sum(p) == 0.
--   * calculate_crc_bits.m :  G = G_max(end-length(a)+1:end, :);  p = mod(a*G,2)
--   * get_crc_generator_matrix.m :  G_max = get_crc_generator_matrix(6144, poly)
--     with poly = get_3gpp_crc_polynomial('CRC24A' | 'CRC24B').
--   So for a length-K hard decision a[0..K-1] the CRC syndrome is
--       p = XOR over k of ( a[k] * G_max[(6144-K)+k][:] )   (mod 2),
--   i.e. the matrix is sliced from the TAIL (last K rows of the size-6144
--   matrix) exactly as calculate_crc_bits slices G_max(end-K+1:end,:).
--   crc_ok asserts iff p is all-zero (sum(p) == 0).
--
-- ---------------------------------------------------------------------------
-- GENERATOR MATRIX (mirrors the crc8_parallel.vhdl ROM idiom, generalised to
-- 24 bits and length 6144, built once at elaboration from the SAME recurrence
-- as get_crc_generator_matrix.m so the rows cannot drift from the float model):
--   G_P(end,:) = crc_polynomial_pattern(2:end)               -- last row = poly tail
--   for k = A-1:-1:1
--     G_P(k,:) = xor( [G_P(k+1,2:end), 0],                    -- shift left, 0-fill
--                     G_P(k+1,1) * crc_polynomial_pattern(2:end) )
--   This is the standalone CRC24 core (Decision 1 / Open Question): it leaves
--   the hardware-verified crc8_parallel.vhdl UNTOUCHED (zero regression). It
--   supports BOTH LTE polynomials at run time via is_tb:
--     is_tb = '1' -> CRC24A (transport-block CRC, used when C == 1)
--     is_tb = '0' -> CRC24B (code-block  CRC, used when C  > 1)
--   matching turbo_decoding_chain.m's CB-vs-TB selection.
--
-- ---------------------------------------------------------------------------
-- INTERFACE (streaming, one hard bit per beat, a[0] first):
--   start    : pulse with k_in (= K) and is_tb latched; resets the syndrome
--              accumulator and selects the tail row index (6144-K).
--   in_valid : one decoded hard bit a[k] on bit_in per beat, k = 0..K-1,
--              in forward order (a[0] first). The core XORs in the
--              corresponding generator-matrix row when bit_in = '1'.
--   After K beats, crc_done pulses and crc_ok holds the syndrome==0 result
--   (stable until the next start). The check is a pure function of the
--   streamed bits + K + is_tb (deterministic), so the early-stop point is
--   reproducible bit-for-bit (design.md Decision 3).
--
--   The K bits MUST be the hard decision computed BEFORE any filler->NaN
--   overwrite (the float computes the CRC on c, then sets c(filler)=NaN;
--   design.md Decision 4). The driving top (turbo_decoder_term_top) honours
--   that order.
-- ===========================================================================
entity crc24_check is
  generic (
    K_MAX : integer := 6144;   -- max code-block length (matrix row count)
    W_K   : integer := 13;     -- K port width (6144 -> 13 bits)
    L     : integer := 24      -- CRC length (CRC24A/CRC24B both 24)
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                          -- sync, active-high
    start    : in  std_logic;                          -- latch K/is_tb, reset acc
    k_in     : in  std_logic_vector(W_K-1 downto 0);   -- block length K
    is_tb    : in  std_logic;                          -- '1'=CRC24A, '0'=CRC24B
    in_valid : in  std_logic;                          -- one hard bit per beat
    bit_in   : in  std_logic;                          -- a[k], a[0] first
    crc_done : out std_logic;                          -- one-cycle pulse after K
    crc_ok   : out std_logic                           -- syndrome == 0 (held)
  );
end entity crc24_check;

architecture rtl of crc24_check is

  -- One generator-matrix row.
  subtype crc_row_t is std_logic_vector(L-1 downto 0);
  type gen_matrix_t is array (0 to K_MAX-1) of crc_row_t;

  -- 3GPP CRC polynomial patterns (TS36.212 SS5.1.1; mirrors
  -- get_3gpp_crc_polynomial.m). Stored as the (P+1)-bit pattern with
  -- index 0 = coefficient of D^P (the get_3gpp_crc_polynomial fliplr layout),
  -- length L+1 = 25 bits.  get_crc_generator_matrix uses pattern(2:end), i.e.
  -- the low L coefficients D^(P-1)..D^0 -> here pattern(L-1 downto 0).
  --   CRC24A exponents = [24,23,18,17,14,11,10,7,6,5,4,3,1,0]
  --   CRC24B exponents = [24,23,6,5,1,0]
  function poly_pattern(is_tb_p : std_logic) return std_logic_vector is
    variable v : std_logic_vector(L downto 0) := (others => '0');  -- D^24..D^0
  begin
    -- set coefficient of D^e to 1 for each exponent e
    if is_tb_p = '1' then
      -- CRC24A
      v(24) := '1'; v(23) := '1'; v(18) := '1'; v(17) := '1'; v(14) := '1';
      v(11) := '1'; v(10) := '1'; v(7) := '1';  v(6) := '1';  v(5) := '1';
      v(4) := '1';  v(3) := '1';  v(1) := '1';  v(0) := '1';
    else
      -- CRC24B
      v(24) := '1'; v(23) := '1'; v(6) := '1'; v(5) := '1'; v(1) := '1';
      v(0) := '1';
    end if;
    return v;
  end function;

  -- tail = crc_polynomial_pattern(2:end) in get_crc_generator_matrix.m terms:
  -- the L low-order coefficients D^(L-1) .. D^0. With our v indexed by exponent
  -- (v(e) = coeff of D^e), pattern(2:end) MATLAB layout (D^P first after the
  -- leading D^P term... see below) maps to the column order MATLAB uses.
  --
  -- MATLAB layout note: crc_polynomial (after fliplr) is
  --   [coeff(D^P), coeff(D^(P-1)), ..., coeff(D^0)]  (length P+1, P=L=24).
  -- pattern(2:end) = [coeff(D^(P-1)), ..., coeff(D^0)]  (length L).
  -- The generator-matrix COLUMN j (1..L, MATLAB) therefore holds coeff(D^(P-j)).
  -- We store each row as a std_logic_vector(L-1 downto 0) whose bit (L-1) is
  -- MATLAB column 1 (= coeff D^(P-1)) and bit 0 is MATLAB column L (= coeff D^0)
  -- -- a fixed, internally-consistent column convention. Since calculate_crc_bits
  -- only tests whether the WHOLE syndrome vector is zero (sum(p)==0), any fixed
  -- bijective column ordering gives the identical all-zero test; the convention
  -- here matches the crc8_parallel.vhdl MSB-first row layout.
  function tail_vec(pat : std_logic_vector) return crc_row_t is
    variable t : crc_row_t;
  begin
    -- MATLAB pattern(2:end) = [D^(L-1), D^(L-2), ..., D^0]; place D^(L-1) at
    -- bit L-1 down to D^0 at bit 0.
    for j in 0 to L-1 loop
      t(j) := pat(j);            -- bit j = coeff of D^j
    end loop;
    return t;
  end function;

  -- Build the size-K_MAX generator matrix from the recurrence, identical to
  -- get_crc_generator_matrix.m (1-based -> 0-based here):
  --   G(K_MAX-1) = tail
  --   for k = K_MAX-2 downto 0:
  --     G(k) = ( G(k+1) shifted toward D^(higher) by one ) XOR
  --            ( leadingbit(G(k+1)) * tail )
  -- In MATLAB the shift is [G(k+1,2:end),0] (drop column 1, append 0 at the
  -- end) and the lead is G(k+1,1) (column 1). In our bit layout column 1 =
  -- bit L-1 (MSB) and the append-0-at-end = LSB 0; so:
  --   shifted = G(k+1) << 1   (drop MSB, shift up, LSB <= 0)
  --   lead    = G(k+1)(L-1)   (the dropped MSB)
  function build_matrix(is_tb_p : std_logic) return gen_matrix_t is
    variable g    : gen_matrix_t;
    variable tail : crc_row_t;
    variable nxt  : crc_row_t;
    variable shf  : crc_row_t;
    variable lead : std_logic;
  begin
    tail := tail_vec(poly_pattern(is_tb_p));
    g(K_MAX-1) := tail;
    for k in K_MAX-2 downto 0 loop
      nxt  := g(k+1);
      lead := nxt(L-1);                       -- MATLAB column 1 = our MSB
      shf  := nxt(L-2 downto 0) & '0';        -- [G(2:end),0]  -> shift up, 0-fill
      if lead = '1' then
        g(k) := shf xor tail;
      else
        g(k) := shf;
      end if;
    end loop;
    return g;
  end function;

  -- Two precomputed generator matrices (elaboration-time constants).
  constant GEN_A : gen_matrix_t := build_matrix('1');   -- CRC24A
  constant GEN_B : gen_matrix_t := build_matrix('0');   -- CRC24B

  -- Streaming state.
  signal syndrome : crc_row_t := (others => '0');
  signal row_idx  : integer range 0 to K_MAX := 0;   -- 0-based matrix row
  signal cnt      : integer range 0 to K_MAX := 0;   -- bits consumed
  signal Kr       : integer range 0 to K_MAX := 0;
  signal tb_sel   : std_logic := '0';
  signal ok_r     : std_logic := '0';
  signal done_r   : std_logic := '0';

begin

  crc_ok   <= ok_r;
  crc_done <= done_r;

  process (clk)
    variable g_row : crc_row_t;
  begin
    if rising_edge(clk) then
      done_r <= '0';

      if rst = '1' then
        syndrome <= (others => '0');
        row_idx  <= 0;
        cnt      <= 0;
        Kr       <= 0;
        tb_sel   <= '0';
        ok_r     <= '0';
      else
        if start = '1' then
          -- Latch K / poly; reset the syndrome. Tail-index: the first streamed
          -- bit a[0] uses generator row (K_MAX - K)  (== MATLAB G_max row
          -- end-K+1, 0-based (K_MAX-K)).
          Kr       <= to_integer(unsigned(k_in));
          tb_sel   <= is_tb;
          row_idx  <= K_MAX - to_integer(unsigned(k_in));
          cnt      <= 0;
          syndrome <= (others => '0');
          ok_r     <= '0';
        elsif in_valid = '1' then
          -- Select the generator row for this bit from the chosen polynomial.
          if tb_sel = '1' then
            g_row := GEN_A(row_idx);
          else
            g_row := GEN_B(row_idx);
          end if;

          if bit_in = '1' then
            syndrome <= syndrome xor g_row;
          end if;

          if cnt = Kr - 1 then
            -- last bit consumed: evaluate syndrome == 0 (account for this beat).
            if bit_in = '1' then
              if (syndrome xor g_row) = crc_row_t'(others => '0') then
                ok_r <= '1';
              else
                ok_r <= '0';
              end if;
            else
              if syndrome = crc_row_t'(others => '0') then
                ok_r <= '1';
              else
                ok_r <= '0';
              end if;
            end if;
            done_r <= '1';
            cnt    <= 0;
          else
            cnt     <= cnt + 1;
            row_idx <= row_idx + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
