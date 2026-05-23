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
--   * The w arrays are read SYNCHRONOUSLY (registered read address) so they
--     infer Cyclone II M4K block RAM; the one-cycle read latency is absorbed
--     by an S_PRIME beat so the emitted (e_bit, out_valid, last) stream is
--     identical cycle-for-cycle (modulo a uniform one-cycle pipeline-fill that
--     the read FSM hides).
--   * The loop index jj is bounded for synthesis.
-- The standard-defined behaviour (which w positions are read, in what order,
-- skipping fillers) is unchanged.
--
-- M4K block-RAM inference rework (add-fpga-block-ram-inference, stage 1):
--   The TS36.212 w-construction writes THREE positions per loaded column
--   (w[k]=v1, w[K_Pi+2k]=v2, w[K_Pi+2k+1]=v3). A single M4K write port does
--   one write/cycle, and Quartus II 13.0sp1 also refuses to map an array whose
--   write lives inside the synchronous-reset-guarded FSM body. Both problems
--   are solved together by BANK-SPLITTING w into three 1W/1R simple-dual-port
--   arrays sized K_Pi each -- w_sys (systematic, row 1), w_ev (even parity,
--   row 2), w_od (odd parity, row 3) -- each written by ONE port at column
--   index cidx, in a dedicated unconditional clocked memory process (the write
--   is lifted out of the reset/case nest; the FSM drives only the write-data /
--   write-enable / write-column and the read address). The circular READ maps
--   a w position pos in [0,K_w) back to its bank: pos<K_Pi -> w_sys[pos];
--   else r=pos-K_Pi, r even -> w_ev[r/2], r odd -> w_od[r/2] (r/2 = r>>1,
--   divider-free). The bank select is registered alongside the per-bank
--   registered reads so the one-cycle-later data mux picks the right bank.
--   Bit-exactness is unchanged: the same w contents are presented before the
--   read begins; the cocotb circular_buffer lane is the gate. The ramstyle
--   "M4K" attribute pins the intent. (rate_matching + encoder buffers are
--   stages 2-3.)
--   Recorded Quartus II 13.0sp1 (EP2C35F672C6) synthesis-oracle result, full
--   KW_MAX=18528 (K_Pi up to 6176) standalone harness, before -> after:
--     Total memory bits : 0       -> 49,152 (of 483,840, 10%)
--     M4K block RAM      : 0       -> 12 (of 105, 11%; altsyncram inferred,
--                                    simple-dual-port, RDW=OLD_DATA)
--     Total logic elements: 115,074 (2.5x+ over EP2C35) -> 584 (2%); fits.
--     Fmax (CLOCK_50)    : closes 50 MHz; restricted Fmax 96.48 MHz,
--                          worst-case setup slack +9.635 ns, hold +0.391 ns.
--   i.e. the w memories now infer M4K instead of collapsing to LE registers.
--   Integrated full-K=6144 tx_chain_top fit (stage 4, with the sibling encoder
--   + rate-match M4K fixes): 22/105 M4K, 90,112 memory bits, 1,716/33,216 LE,
--   605 registers, Fmax 89.33 MHz on CLOCK_50 -- the whole chain fits the
--   EP2C35 via block RAM (was ~85k LE as logic = did not fit).
entity circular_buffer is
  generic (
    -- Max w-buffer depth K_w = 3*K_Pi. Defaults to the TS36.212 maximum
    -- (3*6176 = 18528) so every existing instantiation/testbench is
    -- byte-identical; board demos override it small (sized for their K_Pi) to
    -- fit. All derived counter ranges (N_cb, k0, jj, pos, q_*, m_*) scale with
    -- this generic, so shrinking it shrinks the whole core.
    KW_MAX : integer := 3 * 6176                       -- 18528
  );
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
  -- Bank-split w: three 1W/1R arrays of depth K_Pi_max = KW_MAX/3, each
  -- written by one port (systematic / even-parity / odd-parity), so each is a
  -- clean single-write-port M4K candidate. KW_MAX is always 3*K_Pi for the
  -- instantiated max, so the integer divide is exact.
  constant BANK_MAX : integer := KW_MAX / 3;        -- max per-bank depth (K_Pi)
  type bit_arr is array (0 to BANK_MAX-1) of std_logic;
  signal w_sys_bit  : bit_arr := (others => '0');   -- row 1 (systematic)
  signal w_sys_fill : bit_arr := (others => '0');
  signal w_ev_bit   : bit_arr := (others => '0');   -- row 2 (even parity)
  signal w_ev_fill  : bit_arr := (others => '0');
  signal w_od_bit   : bit_arr := (others => '0');   -- row 3 (odd parity)
  signal w_od_fill  : bit_arr := (others => '0');

  -- Pin block-RAM intent (Cyclone II: M4K is the only block-RAM flavour). The
  -- structural fix (single write port + write lifted out of the reset-guarded
  -- FSM body) is what makes it infer; the attribute guards the intent so a
  -- future edit that re-buries the write fails loudly rather than silently
  -- reverting to LE registers.
  attribute ramstyle : string;
  attribute ramstyle of w_sys_bit  : signal is "M4K";
  attribute ramstyle of w_sys_fill : signal is "M4K";
  attribute ramstyle of w_ev_bit   : signal is "M4K";
  attribute ramstyle of w_ev_fill  : signal is "M4K";
  attribute ramstyle of w_od_bit   : signal is "M4K";
  attribute ramstyle of w_od_fill  : signal is "M4K";

  -- ----- Write side (FSM-driven controls; the array write itself lives in a
  -- dedicated unconditional memory process, NOT in the reset/case nest). -----
  signal wr_en   : std_logic := '0';                -- load this column now
  signal wr_col  : integer range 0 to BANK_MAX-1 := 0;  -- column index = cidx
  signal wr_sys_bit, wr_sys_fill : std_logic := '0';    -- v1
  signal wr_ev_bit,  wr_ev_fill  : std_logic := '0';    -- v2
  signal wr_od_bit,  wr_od_fill  : std_logic := '0';    -- v3

  -- ----- Synchronous-read pipeline. rd_addr is a w position in [0,K_w). It is
  -- decoded combinationally to a per-bank address + a bank-select tag; the
  -- per-bank reads register one cycle later, and the tag (registered alongside)
  -- selects which bank's data lands in rd_bit/rd_fill. ----------------------
  signal rd_addr : integer range 0 to KW_MAX-1 := 0;
  signal rd_bit  : std_logic := '0';
  signal rd_fill : std_logic := '0';

  -- bank-select tag for the address issued last edge: 0=sys, 1=ev, 2=od.
  signal rd_sel  : integer range 0 to 2 := 0;
  -- per-bank registered read data (each a registered read of its own RAM).
  signal rd_sys_bit, rd_sys_fill : std_logic := '0';
  signal rd_ev_bit,  rd_ev_fill  : std_logic := '0';
  signal rd_od_bit,  rd_od_fill  : std_logic := '0';

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

  -- ---------------------------------------------------------------------------
  -- Dedicated memory process: the three bank arrays' writes and registered
  -- reads live here ONLY, with NO synchronous reset on the array bodies (the
  -- M4K write-port template the reduced test confirmed). The FSM drives the
  -- write controls (wr_en/wr_col/wr_*) and the read address (rd_addr); it never
  -- touches the arrays directly. Each bank has exactly one write port.
  -- ---------------------------------------------------------------------------
  mem : process (clk)
    variable r, ba : integer;
  begin
    if rising_edge(clk) then
      -- One write per bank per loaded column (single-write-port, M4K-clean).
      if wr_en = '1' then
        w_sys_bit(wr_col)  <= wr_sys_bit;
        w_sys_fill(wr_col) <= wr_sys_fill;
        w_ev_bit(wr_col)   <= wr_ev_bit;
        w_ev_fill(wr_col)  <= wr_ev_fill;
        w_od_bit(wr_col)   <= wr_od_bit;
        w_od_fill(wr_col)  <= wr_od_fill;
      end if;

      -- Registered reads of all three banks at the decoded bank address, plus
      -- the registered bank-select tag. rd_addr is a w position in [0,K_w);
      -- decode it to (bank, bank-address): pos<K_Pi -> sys[pos]; else r=pos-K_Pi
      -- with r even -> ev[r/2], r odd -> od[r/2] (r/2 = r>>1, divider-free).
      if rd_addr < K_Pi then
        ba := rd_addr;
        rd_sel <= 0;
      else
        r  := rd_addr - K_Pi;
        ba := r / 2;                  -- exact shift-right-1 (constant divisor 2)
        if (r mod 2) = 0 then
          rd_sel <= 1;                -- even parity bank
        else
          rd_sel <= 2;                -- odd parity bank
        end if;
      end if;
      rd_sys_bit  <= w_sys_bit(ba);
      rd_sys_fill <= w_sys_fill(ba);
      rd_ev_bit   <= w_ev_bit(ba);
      rd_ev_fill  <= w_ev_fill(ba);
      rd_od_bit   <= w_od_bit(ba);
      rd_od_fill  <= w_od_fill(ba);
    end if;
  end process mem;

  -- Bank-select mux: rd_bit/rd_fill hold the data for the address presented on
  -- the previous edge, exactly like the old single-array sync read did.
  rd_bit  <= rd_sys_bit  when rd_sel = 0 else
             rd_ev_bit   when rd_sel = 1 else rd_od_bit;
  rd_fill <= rd_sys_fill when rd_sel = 0 else
             rd_ev_fill  when rd_sel = 1 else rd_od_fill;

  process (clk)
    variable rtc, kw, ncb : integer;
  begin
    if rising_edge(clk) then
      ov  <= '0';
      lst <= '0';
      wr_en <= '0';                 -- write only on the cycle a v column lands

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
              -- Drive the single-write-port memory process: one write per bank
              -- at column cidx (w_sys[cidx]=v1, w_ev[cidx]=v2, w_od[cidx]=v3).
              -- The actual array writes happen in the mem process this edge.
              wr_en       <= '1';
              wr_col      <= cidx;
              wr_sys_bit  <= v1_bit;  wr_sys_fill <= v1_fill;
              wr_ev_bit   <= v2_bit;  wr_ev_fill  <= v2_fill;
              wr_od_bit   <= v3_bit;  wr_od_fill  <= v3_fill;
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
