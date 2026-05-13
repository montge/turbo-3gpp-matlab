## ADDED Requirements

### Requirement: Recursive systematic convolutional constituent encoder

The system SHALL provide a rate-1 constituent encoder for a recursive systematic convolutional code with 3 memory elements, generator polynomial `[1, 1, 0, 1]`, and feedback polynomial `[1, 0, 1, 1]`, as specified in §§5.1.3.2.1–5.1.3.2.2 of TS36.212.

For a `K`-bit input row vector `c`, the encoder SHALL return two `K + 3`-element row vectors `(z, x)` where:

- The shift register starts in state `(s1, s2, s3) = (0, 0, 0)`.
- For each input bit `c(k)` (`k = 0..K-1`): `s1' = mod(c(k) + s2 + s3, 2)`, `s2' = s1`, `s3' = s2`. The systematic output is `x(k) = c(k)` and the parity output is `z(k) = mod(s1' + s1 + s3, 2)`.
- For the three trellis-termination steps (`k = K, K+1, K+2`), the encoder SHALL clock zeros into the feedback path (`s1' = 0`) and emit the termination systematic bit `x(k) = mod(s2 + s3, 2)` and parity bit `z(k) = mod(s1' + s1 + s3, 2)`.

#### Scenario: Output shape
- **WHEN** `constituent_encoder(c)` is called with a `K`-bit row vector `c`
- **THEN** both returned vectors have length `K + 3`

#### Scenario: Zero input produces zero output
- **WHEN** `constituent_encoder(zeros(1, K))` is called for any `K ≥ 1`
- **THEN** both returned vectors are all-zero of length `K + 3`

#### Scenario: Trellis termination forces zero state
- **WHEN** the encoder finishes processing the three termination steps
- **THEN** the shift register state is `(0, 0, 0)`

### Requirement: Rate-1/3 parallel-concatenated turbo encoder

The system SHALL provide a rate-1/3 turbo encoder, defined in §5.1.3.2 of TS36.212, that:

1. Accepts a `K`-bit code block `c` and a length-`K` interleaver pattern `pi` (zero-based indices forming a permutation of `0..K-1`).
2. Treats any `NaN` entries in `c` as filler bits, replacing them with `0` before encoding.
3. Computes `c_prime = c(pi + 1)`, then encodes both `c` and `c_prime` with the constituent encoder to produce `(z, x)` and `(z_prime, x_prime)`.
4. Returns a `3 × (K + 4)` matrix `d` where:
   - For `k = 0..K-1`: `d(:, k+1) = [x(k+1); z(k+1); z_prime(k+1)]`.
   - For the trellis-termination columns `K+1..K+4`: `d(:, K+1) = [x(K+1); z(K+1); x(K+2)]`, `d(:, K+2) = [z(K+2); x(K+3); z(K+3)]`, `d(:, K+3) = [x_prime(K+1); z_prime(K+1); x_prime(K+2)]`, `d(:, K+4) = [z_prime(K+2); x_prime(K+3); z_prime(K+3)]`.
   - Rows 1 and 2 at filler-bit positions are set to `NaN`.

#### Scenario: Output shape
- **WHEN** `turbo_encoder(c, pi)` is called with a `K`-bit code block
- **THEN** the result has 3 rows and `K + 4` columns

#### Scenario: Interleaver length mismatch
- **WHEN** `turbo_encoder(c, pi)` is called with `length(pi) ≠ length(c)`
- **THEN** the call raises an error

#### Scenario: Filler bit propagation
- **WHEN** the input code block has `NaN` entries representing filler bits
- **THEN** rows 1 and 2 of the corresponding columns of the output equal `NaN`, and row 3 contains the parity bit produced by treating the filler as zero
