library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Circular buffer, TS36.212 SS5.1.4.1.2. Bit-for-bit equivalent of
-- circular_buffer.m. Given the 3 x K_Pi sub-block-interleaved matrix v
-- (each element a bit + filler flag) and (N_ref, I_LBRM, rv_idx, E), builds
-- w (K_w = 3*K_Pi: row1, then rows 2/3 interleaved), computes N_cb and the
-- start offset k_0, and streams E non-filler bits read circularly from w.
--
-- Synthesis-hardened (DE2/Cyclone II): the sim-only constructs of v1 have
-- been replaced WITHOUT changing a single output bit (the circular_buffer
-- cocotb lane stays bit-exact vs the committed golden vectors):
--   * The non-power-of-2 divide q = ceil(N_cb/(8*R_TC)) is now a divider-free
--     accumulate-and-count recurrence over the constant step = 8*R_TC
--     (= K_Pi/4), run once per block in a dedicated S_QCALC state.
--   * The non-power-of-2 modulo pos = (k_0+j) mod N_cb is now a running pos
--     register (increment + conditional -N_cb each read step); the one-time
--     pos = k_0 mod N_cb is computed by a divider-free shift/compare-subtract
--     recurrence in S_K0MOD.
--   * The two w_bit/w_fill arrays are read SYNCHRONOUSLY (registered read
--     address) so they infer Cyclone II M4K block RAM; the one-cycle read
--     latency is absorbed by an S_PRIME beat so the emitted
--     (e_bit, out_valid, last) stream is identical cycle-for-cycle (modulo a
--     uniform one-cycle pipeline-fill that the read FSM hides).
--   * The loop index jj is bounded for synthesis.
-- The standard-defined behaviour (which w positions are read, in what order,
-- skipping fillers) is unchanged.
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

  -- Synchronous-read pipeline registers for w_bit/w_fill (registered read
  -- address -> M4K). rd_bit/rd_fill hold the data read for the address that
  -- was presented on the previous clock edge.
  signal rd_addr : integer range 0 to KW_MAX-1 := 0;
  signal rd_bit  : std_logic := '0';
  signal rd_fill : std_logic := '0';

  type state_t is (S_IDLE, S_LOAD, S_QCALC, S_K0MOD, S_PRIME, S_READ, S_DONE);
  signal st : state_t := S_IDLE;

  signal K_Pi  : integer range 0 to 6176 := 0;
  signal K_w   : integer range 0 to KW_MAX := 0;
  signal R_TC  : integer range 0 to 193 := 0;
  signal N_cb  : integer range 0 to KW_MAX := 0;
  signal k0    : integer range 0 to 8*KW_MAX := 0;
  signal Ev    : integer range 0 to 65535 := 0;
  signal NrefR : integer range 0 to 65535 := 0;
  signal RvR   : integer range 0 to 3 := 0;
  signal LbrmR : std_logic := '0';
  signal cidx  : integer range 0 to 6176 := 0;       -- v column counter
  signal jj    : integer range 0 to 8*KW_MAX := 0;
  signal kk    : integer range 0 to 65535 := 0;

  -- Divider-free q = ceil(N_cb/(8*R_TC)) accumulate-and-count state.
  signal q_step : integer range 0 to KW_MAX := 0;    -- 8*R_TC (= K_Pi/4)
  signal q_acc  : integer range 0 to 2*KW_MAX := 0;
  signal q_cnt  : integer range 0 to KW_MAX := 0;

  -- Divider-free k_0 mod N_cb (shift/compare-subtract) state.
  signal m_rem  : integer range 0 to 8*KW_MAX := 0;  -- running remainder
  signal m_sub  : integer range 0 to 8*KW_MAX := 0;  -- N_cb << shift
  signal pos    : integer range 0 to KW_MAX-1 := 0;  -- running read index

  signal ov, eb, lst : std_logic := '0';
begin
  out_valid <= ov;
  e_bit     <= eb;
  last      <= lst;

  process (clk)
    variable rtc, kw, ncb : integer;
  begin
    if rising_edge(clk) then
      ov  <= '0';
      lst <= '0';

      -- Synchronous-read of w_bit/w_fill: data for the address presented on
      -- the previous edge appears here. This is the M4K-inferable read.
      rd_bit  <= w_bit(rd_addr);
      rd_fill <= w_fill(rd_addr);

      if rst = '1' then
        st <= S_IDLE;
      else
        case st is
          when S_IDLE =>
            if start = '1' then
              -- Out-of-contract guard: K_Pi=0 / E=0 / (LBRM with N_ref=0)
              -- would drive divide/mod-by-zero in the compute states. Defined
              -- safe abort. Valid golden inputs (K_Pi>=64, E>0, N_ref>0)
              -- never take this path -> behaviour bit-exact.
              if unsigned(k_pi_in) = 0 or unsigned(e_in) = 0
                 or (i_lbrm = '1' and unsigned(n_ref_in) = 0) then
                st <= S_DONE;
              else
                K_Pi  <= to_integer(unsigned(k_pi_in));
                Ev    <= to_integer(unsigned(e_in));
                NrefR <= to_integer(unsigned(n_ref_in));
                RvR   <= to_integer(unsigned(rv_in));
                LbrmR <= i_lbrm;
                cidx  <= 0;
                st    <= S_LOAD;
              end if;
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
                -- Set up the divider-free q recurrence: q = ceil(ncb/step),
                -- step = 8*R_TC = 8*(K_Pi/32) = K_Pi/4.
                rtc := K_Pi / 32;            -- exact (K_Pi multiple of 32)
                kw  := 3 * K_Pi;
                if LbrmR = '0' then
                  ncb := kw;
                elsif NrefR < kw then
                  ncb := NrefR;
                else
                  ncb := kw;
                end if;
                R_TC   <= rtc;
                K_w    <= kw;
                N_cb   <= ncb;
                q_step <= 8 * rtc;           -- = K_Pi/4
                q_acc  <= 0;
                q_cnt  <= 0;
                st     <= S_QCALC;
              else
                cidx <= cidx + 1;
              end if;
            end if;

          -- Divider-free q = ceil(N_cb / (8*R_TC)): accumulate step until it
          -- reaches/exceeds N_cb, counting the steps. With N_cb>=1 and step>=1
          -- this yields exactly ceil(N_cb/step) = the original integer
          -- (ncb+step-1)/step. Runs once per block (latency irrelevant).
          when S_QCALC =>
            if q_acc >= N_cb then
              -- q = q_cnt. k0 = R_TC*(2*q*rv + 2). Seed the k0-mod recurrence.
              k0    <= R_TC * (2*q_cnt*RvR + 2);
              m_rem <= R_TC * (2*q_cnt*RvR + 2);
              m_sub <= N_cb;
              st    <= S_K0MOD;
            else
              q_acc <= q_acc + q_step;
              q_cnt <= q_cnt + 1;
            end if;

          -- Divider-free pos0 = k_0 mod N_cb via shift/compare-subtract:
          -- grow m_sub = N_cb<<s while it still fits in m_rem, then subtract
          -- the largest fitting shifted N_cb each step, halving m_sub, until
          -- m_sub < N_cb. m_rem then holds k_0 mod N_cb. Bounded by ~ the bit
          -- width of k_0 (one step per shift level), latency irrelevant.
          when S_K0MOD =>
            if m_rem < N_cb then
              pos    <= m_rem;          -- pos0 = k_0 mod N_cb
              rd_addr <= m_rem;         -- present pos0 to the sync-read RAM
              jj     <= 0;
              kk     <= 0;
              st     <= S_PRIME;
            elsif m_sub * 2 <= m_rem then
              m_sub <= m_sub * 2;       -- grow shifted divisor while it fits
            elsif m_rem >= m_sub then
              m_rem <= m_rem - m_sub;   -- subtract, keep current m_sub
            else
              m_sub <= m_sub / 2;       -- shrink shifted divisor
            end if;

          -- Pipeline-fill beat: pos0 was presented to the RAM in S_K0MOD; its
          -- data lands in rd_bit/rd_fill at THIS edge. Advance pos and present
          -- pos1 so S_READ always consumes the data for the address issued one
          -- edge earlier. No output here (absorbs the one-cycle read latency).
          when S_PRIME =>
            if pos + 1 = N_cb then
              pos     <= 0;
              rd_addr <= 0;
            else
              pos     <= pos + 1;
              rd_addr <= pos + 1;
            end if;
            jj <= 1;                    -- jj counts positions already issued
            st <= S_READ;

          -- Stream: rd_bit/rd_fill hold w(pos for jj-1); register outputs for
          -- that position (matching the original schedule, shifted by the
          -- single pipeline-fill beat). Concurrently issue the next address.
          when S_READ =>
            if jj > 8*KW_MAX then
              st <= S_DONE;            -- safety cap (should never hit)
            else
              -- advance running pos / next read address
              if pos + 1 = N_cb then
                pos     <= 0;
                rd_addr <= 0;
              else
                pos     <= pos + 1;
                rd_addr <= pos + 1;
              end if;
              jj <= jj + 1;
              if rd_fill = '0' then
                eb <= rd_bit;
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
