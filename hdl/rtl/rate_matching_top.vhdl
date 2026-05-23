library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Integrated rate matching, TS36.212 SS5.1.4.1. Bit-for-bit equivalent of
-- rate_matching(d, N_ref, I_LBRM, rv_idx, E):
--   v = [subblock_interleaver(d(1,:),0);
--        subblock_interleaver(d(2,:),1);
--        subblock_interleaver(d(3,:),2)];
--   e = circular_buffer(v, N_ref, I_LBRM, rv_idx, E);
--
-- Wires three UNMODIFIED subblock_interleaver instances (idx 0/1/2, run in
-- lockstep so element k of all three is presented on the same cycle) and one
-- UNMODIFIED circular_buffer. Only the orchestration FSM + the 3xD input
-- buffer are new. Sim-first (sub-cores keep their arithmetic).
--
-- Synthesis-hardened (DE2/Cyclone II): the three D-input buffers d1/d2/d3buf
-- are read SYNCHRONOUSLY (registered read address -> M4K block RAM) instead of
-- the original combinational (async) read, WITHOUT changing a single output
-- bit (the rate_matching_top / tx_chain_top cocotb lanes stay bit-exact vs the
-- committed golden vectors). The one-cycle read latency is absorbed by a single
-- pipeline-register beat: each cycle the subblock taps (read address + filler +
-- valid) are registered, the buffer data lands one edge later, and v_valid to
-- circular_buffer is driven by the registered valid -- so the v columns loaded
-- into the circular buffer are byte-identical, only uniformly shifted by the
-- one-cycle pipeline fill that this FSM hides.
--
-- M4K block-RAM inference (add-fpga-block-ram-inference, stage 2): the three
-- d1/d2/d3buf WRITES are LIFTED OUT of the reset-guarded FSM body into a
-- dedicated unconditional clocked memory process (mem_proc). Quartus II
-- 13.0sp1 refuses to map an array to M4K when its write is nested inside the
-- `if rst='1' then .. else case st ..` synchronous-reset branch (it reads that
-- as a reset/clear on the array body, violating the M4K write-port template,
-- and falls back to LE registers -> `Total memory bits : 0`). With the write
-- at the top level of its own clocked process -- gated only by a write-enable
-- the FSM drives, never by reset -- each buffer is a clean 1W/1R simple-dual-
-- port M4K (`ramstyle="M4K"`), bit-exact to the golden vectors. The reset still
-- controls the FSM/counters in the control process; it just never touches the
-- array contents. Read side (registered-address sync read) is unchanged.
--
-- Verified (Quartus II 13.0sp1, EP2C35F672C6, DMAX=6148 default, isolated
-- rate_matching_top synthesis harness): d1/d2/d3buf each infer as an
-- altsyncram Simple-Dual-Port M4K (8192 memory bits each). Analysis & Synthesis
-- Total memory bits 0 -> 24,576; LE 110,000 -> 79,023; registers 49,689 ->
-- 37,392; M4Ks 0 -> 6 (each buffer spans 2 M4K at 6148 deep). cocotb:
-- rate_matching_top + tx_chain_top lanes PASS bit-exact, golden vectors
-- byte-identical. (Device fit + 50 MHz close is the full-chain gate once the
-- sibling circular_buffer + encoder stages also infer M4K.)
entity rate_matching_top is
  generic (
    -- Max input length D the three d-input buffers are sized for. Defaults to
    -- the TS36.212 maximum (6148 = 6144+4) so existing instantiations are
    -- byte-identical; board demos override it small (sized for their D).
    DMAX   : integer := 6148;
    -- Max circular-buffer depth K_w, threaded down to circular_buffer.
    -- Defaults to the TS36.212 maximum (3*6176 = 18528).
    KW_MAX : integer := 3 * 6176                       -- 18528
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    in_start : in  std_logic;                       -- latch D/params, begin
    d_len    : in  std_logic_vector(12 downto 0);   -- D (= K+4 in the chain)
    n_ref_in : in  std_logic_vector(15 downto 0);
    i_lbrm   : in  std_logic;
    rv_in    : in  std_logic_vector(1 downto 0);
    e_in     : in  std_logic_vector(15 downto 0);
    d_valid  : in  std_logic;                       -- a d column this cycle
    d1_in    : in  std_logic;                       -- d(1,k)
    d2_in    : in  std_logic;                       -- d(2,k)
    d3_in    : in  std_logic;                       -- d(3,k)
    out_valid: out std_logic;                        -- e_bit valid this cycle
    e_bit    : out std_logic;
    last     : out std_logic
  );
end entity rate_matching_top;

architecture rtl of rate_matching_top is
  component subblock_interleaver is
    generic ( W : integer := 13 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      d_in : in std_logic_vector(W-1 downto 0);
      idx_in : in std_logic_vector(1 downto 0);
      valid : out std_logic; filler : out std_logic;
      idx_o : out std_logic_vector(W-1 downto 0);
      last : out std_logic
    );
  end component;

  component circular_buffer is
    generic ( KW_MAX : integer := 3 * 6176 );
    port (
      clk : in std_logic; rst : in std_logic; start : in std_logic;
      k_pi_in : in std_logic_vector(13 downto 0);
      n_ref_in : in std_logic_vector(15 downto 0);
      i_lbrm : in std_logic;
      rv_in : in std_logic_vector(1 downto 0);
      e_in : in std_logic_vector(15 downto 0);
      v_valid : in std_logic;
      v1_bit : in std_logic; v1_fill : in std_logic;
      v2_bit : in std_logic; v2_fill : in std_logic;
      v3_bit : in std_logic; v3_fill : in std_logic;
      out_valid : out std_logic; e_bit : out std_logic; last : out std_logic
    );
  end component;

  type bit_arr is array (0 to DMAX-1) of std_logic;
  signal d1buf, d2buf, d3buf : bit_arr := (others => '0');
  -- Belt-and-suspenders: assert M4K block-RAM mapping at the source so a future
  -- edit that re-buries the write fails loudly (wrong resource) rather than
  -- silently reverting to LE. Cyclone II's only block-RAM flavour is M4K.
  attribute ramstyle : string;
  attribute ramstyle of d1buf : signal is "M4K";
  attribute ramstyle of d2buf : signal is "M4K";
  attribute ramstyle of d3buf : signal is "M4K";

  -- Synchronous-read pipeline registers for d1/d2/d3buf (registered read
  -- output -> M4K). rd1/rd2/rd3 hold the buffer data for the address that was
  -- presented (combinationally) on the previous clock edge; the filler/valid
  -- taps are pipelined by the SAME one cycle so each circular_buffer v column
  -- is loaded unchanged, just shifted by one cycle.
  signal rd1, rd2, rd3 : std_logic := '0';
  signal f0_p, f1_p, f2_p : std_logic := '0';  -- pipelined fillers
  signal vv_p : std_logic := '0';              -- pipelined column-valid

  type state_t is (S_IDLE, S_LOADD, S_INIT, S_STREAM, S_WAIT, S_DONE);
  signal st : state_t := S_IDLE;

  signal Dr   : unsigned(12 downto 0) := (others => '0');
  signal KPi  : unsigned(13 downto 0) := (others => '0');
  signal widx : integer range 0 to DMAX := 0;
  -- Write-enable for the lifted memory process: the FSM asserts it (purely
  -- combinationally below) while loading a d column; the array write itself
  -- lives in mem_proc, never under the reset/case nest.
  signal d_we : std_logic := '0';

  signal sub_start, cb_start, cb_vv : std_logic := '0';

  -- subblock instances (0/1/2)
  signal s0_v, s0_f, s0_l : std_logic;
  signal s1_v, s1_f, s1_l : std_logic;
  signal s2_v, s2_f, s2_l : std_logic;
  signal s0_idx, s1_idx, s2_idx : std_logic_vector(12 downto 0);

  signal v1b, v2b, v3b : std_logic;
  signal cb_ov, cb_eb, cb_lst : std_logic;
begin
  i_sub0 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "00",
              valid => s0_v, filler => s0_f, idx_o => s0_idx, last => s0_l);
  i_sub1 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "01",
              valid => s1_v, filler => s1_f, idx_o => s1_idx, last => s1_l);
  i_sub2 : subblock_interleaver
    generic map (W => 13)
    port map (clk => clk, rst => rst, start => sub_start,
              d_in => std_logic_vector(Dr), idx_in => "10",
              valid => s2_v, filler => s2_f, idx_o => s2_idx, last => s2_l);

  -- v(r,k) = filler ? 0 : d_r[idx_o_r]   (synchronous read: rd* is the buffer
  -- data registered one edge after the address; f*_p the matching pipelined
  -- filler). A filler column reads 0 exactly as before.
  v1b <= '0' when f0_p = '1' else rd1;
  v2b <= '0' when f1_p = '1' else rd2;
  v3b <= '0' when f2_p = '1' else rd3;

  i_cb : circular_buffer
    generic map (KW_MAX => KW_MAX)
    port map (clk => clk, rst => rst, start => cb_start,
              k_pi_in => std_logic_vector(KPi),
              n_ref_in => n_ref_in, i_lbrm => i_lbrm,
              rv_in => rv_in, e_in => e_in,
              v_valid => cb_vv,
              v1_bit => v1b, v1_fill => f0_p,
              v2_bit => v2b, v2_fill => f1_p,
              v3_bit => v3b, v3_fill => f2_p,
              out_valid => cb_ov, e_bit => cb_eb, last => cb_lst);

  -- Combinational FSM control.
  sub_start <= '1' when st = S_INIT else '0';
  cb_start  <= '1' when st = S_INIT else '0';
  -- v_valid is the pipelined subblock-valid: each v column reaches the
  -- circular buffer one cycle after the subblock presents it (matching the
  -- registered-address read latency), keeping the loaded columns identical.
  cb_vv     <= vv_p;

  out_valid <= cb_ov when (st = S_WAIT) else '0';
  e_bit     <= cb_eb;
  last      <= cb_lst when (st = S_WAIT) else '0';

  -- Write-enable: load a d column iff in S_LOADD with d_valid. Purely
  -- combinational off the FSM state so the array write in mem_proc is gated
  -- only by this enable, never by the synchronous reset.
  d_we <= '1' when (st = S_LOADD and d_valid = '1') else '0';

  -- Dedicated UNCONDITIONAL clocked memory process (mem_proc). The three buffer
  -- writes are LIFTED here out of the reset-guarded FSM body so each d*buf maps
  -- to an M4K simple-dual-port (Quartus 13.0sp1 will not infer M4K when the
  -- write is nested under `if rst .. else case ..`). No reset on the array
  -- body. Behaviour is identical: under reset the FSM never reaches S_LOADD, so
  -- d_we is '0' and no spurious write occurs; the read side is unchanged.
  mem_proc : process (clk)
  begin
    if rising_edge(clk) then
      -- Synchronous read of d1/d2/d3buf: the read output is registered, so the
      -- data for the subblock index presented at this edge appears next edge
      -- (M4K-inferable). The filler and valid taps are registered (in the
      -- control process) by the same one cycle so each v column the circular
      -- buffer loads is identical, only shifted by one cycle.
      rd1 <= d1buf(to_integer(unsigned(s0_idx)));
      rd2 <= d2buf(to_integer(unsigned(s1_idx)));
      rd3 <= d3buf(to_integer(unsigned(s2_idx)));
      -- Top-level write (1W port each): gated by d_we only.
      if d_we = '1' then
        d1buf(widx) <= d1_in;
        d2buf(widx) <= d2_in;
        d3buf(widx) <= d3_in;
      end if;
    end if;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      f0_p <= s0_f;
      f1_p <= s1_f;
      f2_p <= s2_f;
      vv_p <= s0_v;

      if rst = '1' then
        st <= S_IDLE;
        vv_p <= '0';
      else
        case st is
          when S_IDLE =>
            if in_start = '1' then
              -- Out-of-contract guard: D=0 or D>DMAX would drive invalid
              -- widx evolution / out-of-range buffer access in S_LOADD.
              -- Defined safe abort. Valid D (44..6148) is unaffected ->
              -- behaviour bit-exact.
              if unsigned(d_len) = 0 or to_integer(unsigned(d_len)) > DMAX then
                st <= S_DONE;
              else
                Dr   <= unsigned(d_len);
                -- K_Pi = 32 * ceil(D/32) = ((D+31)>>5)<<5
                KPi  <= shift_left(
                          resize(shift_right(unsigned(d_len) + 31, 5), 14), 5);
                widx <= 0;
                st   <= S_LOADD;
              end if;
            end if;

          when S_LOADD =>
            -- The buffer writes are lifted to mem_proc (gated by d_we, which is
            -- '1' exactly here when d_valid='1'); this process only advances the
            -- write index / state so the write address evolves identically.
            if d_valid = '1' then
              if widx = to_integer(Dr) - 1 then
                st <= S_INIT;
              else
                widx <= widx + 1;
              end if;
            end if;

          when S_INIT =>
            st <= S_STREAM;            -- sub_start + cb_start pulsed

          when S_STREAM =>
            if s0_l = '1' then         -- final sub-block element (K_Pi-1)
              st <= S_WAIT;
            end if;

          when S_WAIT =>
            if cb_lst = '1' then
              st <= S_DONE;
            end if;

          when S_DONE =>
            st <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
