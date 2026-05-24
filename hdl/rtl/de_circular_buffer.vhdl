library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- de_circular_buffer : inverse (soft) circular buffer, TS36.212 SS5.1.4.1.2,
-- RECEIVE side. The P4 (RX-chain) soft mirror of circular_buffer.vhdl.
--
-- The TX circular_buffer READS E non-filler bits circularly from the K_w-long
-- w buffer (start offset k_0, modulo N_cb, skipping filler positions). This
-- core INVERTS that on soft channel LLRs: it walks the IDENTICAL k_0 / N_cb /
-- dummy-skip read order and, for each incoming received LLR e_soft(k),
-- ACCUMULATES it (saturating) into the soft w buffer at the SAME position the
-- TX read visited:  w_soft(pos) += e_soft(k).  Positions the read visits more
-- than once (E > N_cb circular wrap, i.e. HARQ / high coding rate) soft-combine
-- every LLR that landed there; positions the read never visits stay 0 (erasure,
-- no channel information). This is the float de-rate-match loop
--   d_vec(pi(k)+1) += e(k)         (turbo_decoding_chain.m lines 86-93)
-- restricted to the circular-buffer (w) stage, position by position.
--
-- ---------------------------------------------------------------------------
-- BIT-EXACT CONTRACT (oracle = scripts/fixedpoint_de_rate_matching.m; the
-- cocotb lane, change add-fpga-rx-chain-integration stage 4, asserts the
-- de_rate_matching_top output bit-for-bit vs vectors derived from it):
--   * The address recurrence (k_0, N_cb, dummy-skip, running pos) is REUSED
--     VERBATIM from circular_buffer.vhdl -- the divider-free q = ceil(N_cb/
--     (8*R_TC)) accumulate-and-count (S_QCALC), the multiplier-free
--     k_0 = (2*R_TC*rv)*q + 2*R_TC (k0_acc), the shift/compare-subtract
--     pos0 = k_0 mod N_cb (S_K0MOD), and the running pos increment with
--     conditional -N_cb. So the RX scatter order is the EXACT inverse of the
--     TX gather order; any drift surfaces at once in the bit-exact lane.
--   * Saturating soft-combine on the W_DRM grid:
--       w_soft(pos) = sat_add_W_DRM(w_soft(pos), e_soft(k))
--     W_DRM = 16 (Q11.4, [-32768,32767]); ~64x headroom over the worst-case
--     visit sum so it never wraps at the v1 grid (design.md Decision 3).
--   * Filler w positions (v's NaN pad: w_*_fill = '1') are SKIPPED by the read
--     exactly as the TX (the while-loop `~isnan(w(...))` guard); they receive
--     no accumulate and are not output by the de-rate-match scatter.
--
-- Instead of *reading* w (TX) this core *accumulates* INTO w. The filler-skip
-- per position is driven by the SAME w_*_fill flags the TX built; the caller
-- (de_rate_matching_top) pre-loads the soft w banks to 0 (erasure default) and
-- writes the per-position filler flags, then pulses start.
--
-- M4K-FRIENDLY STORAGE (the proven circular_buffer/rate_matching_top recipe):
-- the soft w buffer is bank-split sys/ev/od (each depth K_Pi, signed W_DRM
-- words). Each bank's write is at the top level of a dedicated unconditional
-- clocked memory process (lifted out of the reset/case nest), single write
-- port, and reads are registered (synchronous) -- the Quartus II 13.0sp1 M4K
-- simple-dual-port template. ramstyle="M4K" pins the intent. The fill-flag
-- banks (1-bit) are tiny and shared from the caller.
--
-- The accumulate is a read-modify-write: present pos one cycle ahead, the
-- registered bank read returns w_soft(pos), add the LLR (saturating), write
-- back next cycle. Because a wrap may revisit a pos within a few cycles, the
-- RMW pipeline serialises one accumulate per (2-cycle) beat so a revisit always
-- reads the just-written value -- bit-exact with the float sequential loop.
-- ===========================================================================
entity de_circular_buffer is
  generic (
    -- Max w-buffer depth K_w = 3*K_Pi (TS36.212 max 3*6176 = 18528). Board
    -- demos override small. Mirrors circular_buffer.vhdl.
    KW_MAX : integer := 3 * 6176;                      -- 18528
    -- Soft-combine accumulator width (design.md Decision 3 pin).
    W_DRM  : integer := 16                             -- Q11.4 accumulator
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    start    : in  std_logic;                          -- begin accumulate
    k_pi_in  : in  std_logic_vector(13 downto 0);      -- K_Pi (mult of 32)
    n_ref_in : in  std_logic_vector(15 downto 0);
    i_lbrm   : in  std_logic;
    rv_in    : in  std_logic_vector(1 downto 0);
    e_in     : in  std_logic_vector(15 downto 0);      -- received length E
    -- Per-position filler flags (the v NaN pad), pre-loaded by the caller into
    -- the three banks; read here to skip filler w positions like the TX read.
    -- Addressed by w-position decode (sys col / ev col / od col).
    fsys_in  : in  std_logic;                          -- w_sys fill at q_col
    fev_in   : in  std_logic;                          -- w_ev  fill at q_col
    fod_in   : in  std_logic;                          -- w_od  fill at q_col
    f_col_o  : out std_logic_vector(13 downto 0);      -- bank col to fetch fill
    -- Received soft LLR stream (W_DRM-grid signed codes; caller quantised to
    -- W_LLR then sign-extended). One e_soft per req pulse / ready handshake.
    e_soft_in: in  std_logic_vector(W_DRM-1 downto 0);
    e_req    : out std_logic;                          -- pull the next e_soft(k)
    -- Soft w bank read-back for the caller's scatter (after done).
    rb_addr  : in  std_logic_vector(13 downto 0);      -- bank column
    rb_sys_o : out std_logic_vector(W_DRM-1 downto 0);
    rb_ev_o  : out std_logic_vector(W_DRM-1 downto 0);
    rb_od_o  : out std_logic_vector(W_DRM-1 downto 0);
    busy     : out std_logic;
    done     : out std_logic                           -- one-cycle pulse
  );
end entity de_circular_buffer;

architecture rtl of de_circular_buffer is
  constant BANK_MAX : integer := KW_MAX / 3;           -- max per-bank depth K_Pi
  constant DRM_MIN  : integer := -(2**(W_DRM-1));
  constant DRM_MAX  : integer :=  (2**(W_DRM-1)) - 1;

  -- Soft w buffer, bank-split sys/ev/od (mirrors circular_buffer's w_sys/ev/od
  -- bit banks, but each word is a signed W_DRM soft LLR accumulator). Each bank
  -- has ONE write port and ONE read port (a SINGLE shared read address; see
  -- below) so it infers the M4K simple-dual-port template, like the decoder's
  -- ext_mem banks -- NOT LE registers.
  -- NO power-up initializer (matches the decoder's ext_mem banks): the S_CLR
  -- sweep zeroes all three banks at runtime before any accumulate (the erasure
  -- default), so an init would only block clean M4K inference.
  type soft_arr is array (0 to BANK_MAX-1) of integer;
  signal w_sys : soft_arr;                             -- row 1 (systematic)
  signal w_ev  : soft_arr;                             -- row 2 (even parity)
  signal w_od  : soft_arr;                             -- row 3 (odd parity)
  attribute ramstyle : string;
  attribute ramstyle of w_sys : signal is "M4K";
  attribute ramstyle of w_ev  : signal is "M4K";
  attribute ramstyle of w_od  : signal is "M4K";

  -- Write port (lifted out of the reset/case nest, single port per bank).
  signal wr_en   : std_logic := '0';
  signal wr_bank : integer range 0 to 2 := 0;          -- 0=sys 1=ev 2=od
  signal wr_col  : integer range 0 to BANK_MAX-1 := 0;
  signal wr_data : integer := 0;
  -- SINGLE shared read address per bank so each bank stays single-read-port
  -- (M4K-inferable). The accumulate RMW read (rd_col, active bank) and the
  -- caller's scatter read-back (rb_addr) are used in DISJOINT phases (accumulate
  -- vs after-done scatter), so one read address suffices: rdaddr = rd_col while
  -- accumulating, = rb_addr during read-back. All three banks register their
  -- read at rdaddr each cycle; the RMW consumes only the active bank's word,
  -- the read-back consumes all three.
  signal rd_col   : integer range 0 to BANK_MAX-1 := 0;
  signal rd_bank  : integer range 0 to 2 := 0;
  signal rdaddr   : integer range 0 to BANK_MAX-1 := 0;   -- shared read address
  signal rd_sys, rd_ev, rd_od : integer := 0;             -- registered bank reads

  -- FSM mirrors circular_buffer's compute/read states; the read step becomes a
  -- 2-phase RMW accumulate (S_RD then S_WR), plus a 3-pass clear of the soft
  -- banks (erasure default) before any accumulate.
  type state_t is (S_IDLE, S_CLR, S_QCALC, S_K0MOD,
                   S_FETCH, S_SKIP, S_RD, S_WR, S_ADV, S_DONE);
  signal st : state_t := S_IDLE;

  signal K_Pi  : integer range 0 to 6176 := 0;
  signal K_w   : integer range 0 to KW_MAX := 0;
  signal R_TC  : integer range 0 to 193 := 0;
  signal N_cb  : integer range 0 to KW_MAX := 0;
  signal Ev    : integer range 0 to 65535 := 0;
  signal NrefR : integer range 0 to 65535 := 0;
  signal RvR   : integer range 0 to 3 := 0;
  signal LbrmR : std_logic := '0';
  signal kk    : integer range 0 to 65535 := 0;        -- LLRs consumed
  signal clr   : integer range 0 to BANK_MAX := 0;

  -- Divider-free q = ceil(N_cb/(8*R_TC)) (verbatim from circular_buffer).
  signal q_step : integer range 0 to KW_MAX := 0;
  signal q_acc  : integer range 0 to 2*KW_MAX := 0;
  signal q_cnt  : integer range 0 to KW_MAX := 0;
  -- Multiplier-free k_0 = (2*R_TC*rv)*q + 2*R_TC (verbatim).
  signal two_rtc : integer range 0 to 8*KW_MAX := 0;
  signal k0_inc  : integer range 0 to 8*KW_MAX := 0;
  signal k0_acc  : integer range 0 to 8*KW_MAX := 0;
  -- Divider-free k_0 mod N_cb (verbatim).
  signal m_rem  : integer range 0 to 8*KW_MAX := 0;
  signal m_sub  : integer range 0 to 8*KW_MAX := 0;
  signal pos    : integer range 0 to KW_MAX-1 := 0;    -- running w position

  -- Decode of the current w position `pos` to (bank, column), and the bank
  -- column presented to the caller for the filler fetch.
  signal cur_bank : integer range 0 to 2 := 0;
  signal cur_col  : integer range 0 to BANK_MAX-1 := 0;

  signal ereq, bsy, dn : std_logic := '0';

  -- Saturating signed add (mirrors the .m sat_add; the HDL RMW accumulate).
  function sat_add(a, b, lo, hi : integer) return integer is
    variable s : integer;
  begin
    s := a + b;
    if s > hi then return hi;
    elsif s < lo then return lo;
    else return s; end if;
  end function;
begin
  e_req <= ereq;
  busy  <= bsy;
  done  <= dn;

  -- Filler-fetch column = the decoded bank column of the current pos (so the
  -- caller returns fsys/fev/fod for the right bank; only the selected bank's
  -- flag is used). Sized to 14 bits (K_Pi width).
  f_col_o <= std_logic_vector(to_unsigned(cur_col, 14));

  -- The caller's scatter read-back is the registered bank read (driven by
  -- rdaddr = rb_addr in S_IDLE, the post-done scatter phase).
  rb_sys_o <= std_logic_vector(to_signed(rd_sys, W_DRM));
  rb_ev_o  <= std_logic_vector(to_signed(rd_ev,  W_DRM));
  rb_od_o  <= std_logic_vector(to_signed(rd_od,  W_DRM));

  -- Shared read address: rd_col while accumulating (S_IDLE means the core is
  -- idle / the caller is doing its read-back, so use rb_addr). One read address
  -- per bank keeps each bank single-read-port -> M4K simple-dual-port.
  rdaddr <= to_integer(unsigned(rb_addr)) when st = S_IDLE else rd_col;

  -- ---- Dedicated memory process: bank writes (single port) + ONE registered
  -- read per bank at the shared rdaddr. Each bank is write-port + read-port =
  -- the M4K simple-dual-port template (ramstyle="M4K"), not LE registers. ----
  mem : process (clk)
  begin
    if rising_edge(clk) then
      -- Per-bank write enable (dedicated, NOT a shared case) -- exactly the
      -- decoder ext_mem template, so each bank is a clean single-write/
      -- single-read SDP and infers M4K (not LE registers).
      if wr_en = '1' and wr_bank = 0 then w_sys(wr_col) <= wr_data; end if;
      if wr_en = '1' and wr_bank = 1 then w_ev(wr_col)  <= wr_data; end if;
      if wr_en = '1' and wr_bank = 2 then w_od(wr_col)  <= wr_data; end if;
      -- single registered read per bank at the shared address.
      rd_sys <= w_sys(rdaddr);
      rd_ev  <= w_ev (rdaddr);
      rd_od  <= w_od (rdaddr);
    end if;
  end process mem;

  process (clk)
    variable rtc, kw, ncb : integer;
    variable r            : integer;
    variable rmw_rd       : integer;   -- active-bank registered read for the RMW
  begin
    if rising_edge(clk) then
      ereq  <= '0';
      dn    <= '0';
      wr_en <= '0';

      if rst = '1' then
        st  <= S_IDLE;
        bsy <= '0';
      else
        case st is
          when S_IDLE =>
            if start = '1' then
              if unsigned(k_pi_in) = 0 or unsigned(e_in) = 0
                 or (i_lbrm = '1' and unsigned(n_ref_in) = 0) then
                st <= S_DONE;
              else
                K_Pi  <= to_integer(unsigned(k_pi_in));
                Ev    <= to_integer(unsigned(e_in));
                NrefR <= to_integer(unsigned(n_ref_in));
                RvR   <= to_integer(unsigned(rv_in));
                LbrmR <= i_lbrm;
                bsy   <= '1';
                clr   <= 0;
                q_cnt <= 0;            -- reuse q_cnt as the per-pass bank index
                st    <= S_CLR;
              end if;
            end if;

          -- Clear the soft w banks to 0 (erasure default) before any
          -- accumulate, via a 3-pass single-write-port sweep: q_cnt selects the
          -- bank (0=sys,1=ev,2=od), clr the column 0..K_Pi-1. On the final pass
          -- compute the derived params (R_TC/K_w/N_cb and the divider-free
          -- k_0/q seeds) -- verbatim from circular_buffer.vhdl S_LOAD.
          when S_CLR =>
            wr_en   <= '1';
            wr_bank <= q_cnt;
            wr_col  <= clr;
            wr_data <= 0;
            if clr = K_Pi - 1 then
              clr <= 0;
              if q_cnt = 2 then
                -- all three banks cleared; now compute params (divider-free).
                rtc := K_Pi / 32;               -- exact (K_Pi multiple of 32)
                kw  := 3 * K_Pi;
                if LbrmR = '0' then
                  ncb := kw;
                elsif NrefR < kw then
                  ncb := NrefR;
                else
                  ncb := kw;
                end if;
                R_TC    <= rtc;
                K_w     <= kw;
                N_cb    <= ncb;
                q_step  <= 8 * rtc;             -- = K_Pi/4
                q_acc   <= 0;
                q_cnt   <= 0;
                two_rtc <= rtc * 2;
                case RvR is
                  when 1      => k0_inc <= rtc * 2;
                  when 2      => k0_inc <= rtc * 4;
                  when 3      => k0_inc <= rtc * 4 + rtc * 2;
                  when others => k0_inc <= 0;
                end case;
                k0_acc <= 0;
                kk     <= 0;
                st     <= S_QCALC;
              else
                q_cnt <= q_cnt + 1;             -- next bank pass
              end if;
            else
              clr <= clr + 1;
            end if;

          -- q = ceil(N_cb/(8*R_TC)) accumulate-and-count (verbatim).
          when S_QCALC =>
            if q_acc >= N_cb then
              m_rem <= k0_acc + two_rtc;        -- k_0
              m_sub <= N_cb;
              st    <= S_K0MOD;
            else
              q_acc  <= q_acc + q_step;
              q_cnt  <= q_cnt + 1;
              k0_acc <= k0_acc + k0_inc;
            end if;

          -- pos0 = k_0 mod N_cb (shift/compare-subtract, verbatim).
          when S_K0MOD =>
            if m_rem < N_cb then
              pos <= m_rem;
              -- decode pos -> (bank,col) and present the filler-fetch column.
              if m_rem < K_Pi then
                cur_bank <= 0;  cur_col <= m_rem;
              else
                r := m_rem - K_Pi;
                if (r mod 2) = 0 then
                  cur_bank <= 1;  cur_col <= r / 2;
                else
                  cur_bank <= 2;  cur_col <= r / 2;
                end if;
              end if;
              st <= S_FETCH;
            elsif m_sub * 2 <= m_rem then
              m_sub <= m_sub * 2;
            elsif m_rem >= m_sub then
              m_rem <= m_rem - m_sub;
            else
              m_sub <= m_sub / 2;
            end if;

          -- Filler-flag fetch beat. cur_col/cur_bank were set in S_K0MOD/S_ADV;
          -- f_col_o (combinational from cur_col) was presented to the caller at
          -- that edge, so the caller's REGISTERED map read (mr_*_f = fsys/fev/
          -- fod_in) is valid THIS cycle and stable into S_SKIP. This beat
          -- absorbs the one-cycle map-read latency (the analogue of the TX
          -- circular_buffer's S_PRIME read-latency beat). No accumulate here.
          when S_FETCH =>
            st <= S_SKIP;

          -- Filler skip: fsys/fev/fod_in (the caller's registered map read for
          -- cur_col) are valid now. If the current w position is filler, advance
          -- pos WITHOUT consuming an LLR (exactly the TX while-loop
          -- `~isnan(w(...))` guard). Otherwise pull the next e_soft and present
          -- the soft-bank read for the RMW accumulate.
          when S_SKIP =>
            if (cur_bank = 0 and fsys_in = '1') or
               (cur_bank = 1 and fev_in  = '1') or
               (cur_bank = 2 and fod_in  = '1') then
              st <= S_ADV;                       -- filler: skip, no accumulate
            else
              ereq    <= '1';                    -- pull e_soft(kk)
              rd_bank <= cur_bank;
              rd_col  <= cur_col;
              st      <= S_RD;
            end if;

          -- RMW read beat: rd_sys/ev/od hold w_soft(rd_col) next edge; e_soft_in
          -- holds the pulled LLR. (e_req was asserted in S_SKIP; the caller
          -- presents e_soft_in this cycle.) rdaddr = rd_col this cycle.
          when S_RD =>
            st <= S_WR;

          -- RMW write beat: w_soft(pos) += e_soft (saturating). The registered
          -- read of pos is the active bank's rd_sys/ev/od (rd_bank = cur_bank);
          -- add and write back the SAME bank/col.
          when S_WR =>
            wr_en   <= '1';
            wr_bank <= cur_bank;
            wr_col  <= cur_col;
            case rd_bank is
              when 0      => rmw_rd := rd_sys;
              when 1      => rmw_rd := rd_ev;
              when others => rmw_rd := rd_od;
            end case;
            wr_data <= sat_add(rmw_rd, to_integer(signed(e_soft_in)),
                               DRM_MIN, DRM_MAX);
            kk <= kk + 1;
            if kk = Ev - 1 then
              st <= S_DONE;                      -- consumed all E LLRs
            else
              st <= S_ADV;
            end if;

          -- Advance the running w position: pos = (pos+1) mod N_cb, then decode
          -- to (bank,col) and present the next filler-fetch column.
          when S_ADV =>
            if pos + 1 = N_cb then
              pos <= 0;
              if K_Pi > 0 then
                cur_bank <= 0;  cur_col <= 0;
              end if;
            else
              pos <= pos + 1;
              if pos + 1 < K_Pi then
                cur_bank <= 0;  cur_col <= pos + 1;
              else
                r := (pos + 1) - K_Pi;
                if (r mod 2) = 0 then
                  cur_bank <= 1;  cur_col <= r / 2;
                else
                  cur_bank <= 2;  cur_col <= r / 2;
                end if;
              end if;
            end if;
            st <= S_FETCH;

          when S_DONE =>
            bsy <= '0';
            dn  <= '1';
            st  <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
