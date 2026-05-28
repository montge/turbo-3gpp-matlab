library ieee;
use ieee.std_logic_1164.all;

-- Rate-1/3 parallel-concatenated turbo encoder, TS36.212 SS5.1.3.2.
-- Bit-for-bit equivalent of turbo_encoder.m. The interleaver pattern is
-- supplied externally: the natural-order block is streamed on c_bit and the
-- interleaved block (c_prime = c(pi+1)) on cprime_bit. The core runs two
-- constituent encoders and assembles the 3 x (K+4) output, streamed
-- column-major (one column triple per cycle while out_valid='1').
--
-- Protocol (driven by the testbench; K-agnostic, no compile-time K):
--   * rst='1' one cycle               -> clears both encoders + sequencer
--   * K data steps  : in_valid='1', in_term='0', c_bit/cprime_bit set
--                      -> emits body column [x; z; z'] each cycle
--   * 3 term steps  : in_valid='1', in_term='1'
--                      -> captures the 3 termination (x,z)/(x',z') pairs
--   * 4 emit cycles : emit='1'
--                      -> streams the 4 trellis-termination columns
entity turbo_encoder is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    in_valid   : in  std_logic;  -- a trellis step is presented this cycle
    in_term    : in  std_logic;  -- '0' = data step, '1' = termination step
    c_bit      : in  std_logic;  -- natural-order code bit (data step)
    cprime_bit : in  std_logic;  -- interleaved-order code bit (data step)
    emit       : in  std_logic;  -- pulse 4 cycles after term to stream tail
    d0         : out std_logic;  -- output column row 1
    d1         : out std_logic;  -- output column row 2
    d2         : out std_logic;  -- output column row 3
    out_valid  : out std_logic
  );
end entity turbo_encoder;

architecture rtl of turbo_encoder is
  component rsc_constituent_encoder is
    port (
      clk  : in  std_logic;
      rst  : in  std_logic;
      en   : in  std_logic;
      term : in  std_logic;
      din  : in  std_logic;
      x_o  : out std_logic;
      z_o  : out std_logic
    );
  end component;

  signal xa, za, xb, zb : std_logic;

  -- Termination buffers, indexed by termination step 0..2.
  -- A = natural encoder, B = interleaved encoder.
  type term_arr is array (0 to 2) of std_logic;
  signal xta, zta, xtb, ztb : term_arr := (others => '0');

  signal tcnt : integer range 0 to 3 := 0;  -- termination step counter
  signal ecnt : integer range 0 to 4 := 0;  -- emit column counter
begin
  enc_a : rsc_constituent_encoder
    port map (clk => clk, rst => rst, en => in_valid,
              term => in_term, din => c_bit, x_o => xa, z_o => za);

  enc_b : rsc_constituent_encoder
    port map (clk => clk, rst => rst, en => in_valid,
              term => in_term, din => cprime_bit, x_o => xb, z_o => zb);

  -- Sequencer: capture termination outputs, advance emit counter.
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        tcnt <= 0;
        ecnt <= 0;
      else
        if in_valid = '1' and in_term = '1' and tcnt < 3 then
          xta(tcnt) <= xa;
          zta(tcnt) <= za;
          xtb(tcnt) <= xb;
          ztb(tcnt) <= zb;
          tcnt <= tcnt + 1;
        end if;
        if emit = '1' and ecnt < 4 then
          ecnt <= ecnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- Combinational output column (Mealy), aligned to the presented step.
  process (in_valid, in_term, emit, ecnt, xa, za, zb,
           xta, zta, xtb, ztb)
  begin
    d0 <= '0';
    d1 <= '0';
    d2 <= '0';
    out_valid <= '0';

    if in_valid = '1' and in_term = '0' then
      -- Body column k: [x(k); z(k); z'(k)]
      d0 <= xa;
      d1 <= za;
      d2 <= zb;
      out_valid <= '1';
    elsif emit = '1' then
      out_valid <= '1';
      case ecnt is
        when 0 =>            -- col K+1: [x(K+1); z(K+1); x(K+2)]
          d0 <= xta(0); d1 <= zta(0); d2 <= xta(1);
        when 1 =>            -- col K+2: [z(K+2); x(K+3); z(K+3)]
          d0 <= zta(1); d1 <= xta(2); d2 <= zta(2);
        when 2 =>            -- col K+3: [x'(K+1); z'(K+1); x'(K+2)]
          d0 <= xtb(0); d1 <= ztb(0); d2 <= xtb(1);
        when 3 =>            -- col K+4: [z'(K+2); x'(K+3); z'(K+3)]
          d0 <= ztb(1); d1 <= xtb(2); d2 <= ztb(2);
        when others =>
          out_valid <= '0';
      end case;
    end if;
  end process;
end architecture rtl;
