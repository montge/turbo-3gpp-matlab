# turbo-decoder Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: maxstar Jacobian logarithm with exact and approximate modes

The system SHALL provide a `maxstar` operator that computes the Jacobian logarithm `log(exp(a) + exp(b)) = max(a, b) + log(1 + exp(-|a - b|))` elementwise. The operator SHALL accept either two equal-size matrices or a single matrix (in which case it reduces column-wise across rows). When a global variable `approx_star` is set to a truthy value, the operator SHALL fall back to the plain `max` approximation. `NaN` differences in `a - b` SHALL be treated as zero so that `NaN` entries on only one side propagate the other side's value through the `max`.

#### Scenario: Exact maxstar identity
- **WHEN** `maxstar(a, b)` is called with `approx_star = false`
- **THEN** the result equals `max(a, b) + log(1 + exp(-abs(a - b)))` elementwise

#### Scenario: Approximate maxstar uses plain max
- **WHEN** `maxstar(a, b)` is called with `approx_star = true`
- **THEN** the result equals `max(a, b)` elementwise

#### Scenario: Column-reduction form
- **WHEN** `maxstar(a)` is called with `a` an `M × N` matrix
- **THEN** the result is a `1 × N` row vector equal to the row-wise maxstar reduction of `a`

### Requirement: Log-BCJR constituent decoder

The system SHALL provide a Log-BCJR decoder for the 8-state constituent code defined by the turbo-encoder spec. The decoder SHALL:

- Accept `(x_a, z_a)`, each a row vector of `K + 3` a-priori LLRs in the `ln[Pr(bit = 0)/Pr(bit = 1)]` convention.
- Compute branch metrics `gamma = gamma_x + gamma_z` from the 16 trellis transitions, where transitions with input `1` contribute `-x_a` and transitions with parity `1` contribute `-z_a`.
- Initialize forward state log-probabilities with state 1 at `0` and all other states at `-inf` (encoder starts in the all-zero state) and run the forward recursion using `maxstar`.
- Initialize backward state log-probabilities with state 1 at `0` and all other states at `-inf` (encoder ends in the all-zero state after termination) and run the backward recursion using `maxstar`.
- Combine alphas and betas with `gamma_z` to compute the `K + 3` extrinsic systematic LLRs `x_e = maxstar(deltas | input=0) - maxstar(deltas | input=1)`.

The decoder SHALL raise an error if `length(x_a) != length(z_a)`.

#### Scenario: LLR length mismatch
- **WHEN** `constituent_decoder(x_a, z_a)` is called with `length(x_a) != length(z_a)`
- **THEN** the call raises an error

### Requirement: Iterative turbo decoder with optional CRC early termination

The system SHALL provide an iterative turbo decoder that:

1. Accepts a `3 × (K + 4)` LLR matrix `d_a`, a length-`K` interleaver pattern `pi`, a `max_iterations` value (a multiple of 0.5), and optionally a CRC generator matrix `G_max`.
2. Locates filler-bit columns from `NaN` entries of `d_a(1, :)` and replaces remaining `NaN` LLRs with `+inf` (logically asserting filler bits are zero with infinite confidence).
3. Splits `d_a` into systematic-and-termination LLR vectors `(x_a, z_a)` for the upper decoder and `(x_prime_a, z_prime_a)` for the lower decoder, consistent with the placement chosen by the turbo encoder.
4. Initializes the extrinsic a-priori `c_a = 0` and iterates half-iterations: upper decode → hard-decide → optional CRC check → interleave → lower decode → de-interleave → hard-decide → optional CRC check, performing `ceil(max_iterations)` whole iterations and skipping the final lower half when `2 * max_iterations` is odd.
5. Returns the `K`-bit hard-decided code block `c` and the number of iterations actually performed (a multiple of 0.5).
6. When `G_max` is supplied, SHALL terminate early as soon as `calculate_crc_bits(c, G_max) == 0`, both before the first iteration and after each half iteration. Filler-bit positions of the returned `c` SHALL be set to `NaN`.

The decoder SHALL raise an error if `size(d_a, 1) != 3`, if `length(pi) != size(d_a, 2) - 4`, or if `max_iterations` is not a multiple of 0.5.

#### Scenario: Decoder shape and iteration count
- **WHEN** `turbo_decoder(d_a, pi, max_iterations)` is called with a valid `d_a` and `max_iterations`
- **THEN** the returned `c` is a length-`K` row vector and `iterations_performed ≤ max_iterations`

#### Scenario: CRC-based early termination
- **WHEN** `turbo_decoder(d_a, pi, max_iterations, G_max)` is called and the decoded `c` satisfies `mod(c * G_max, 2) == 0` at any half iteration
- **THEN** the decoder returns immediately with that `c` and `iterations_performed ≤ max_iterations`

#### Scenario: Filler bits in output
- **WHEN** `d_a(1, :)` contains `NaN` columns indicating filler bits
- **THEN** the corresponding positions of the returned `c` equal `NaN`

#### Scenario: Half-iteration support
- **WHEN** `turbo_decoder` is called with `max_iterations = 0.5`
- **THEN** the decoder performs exactly the upper half iteration and returns

#### Scenario: Invalid iteration count
- **WHEN** `turbo_decoder` is called with `max_iterations` that is not a multiple of 0.5
- **THEN** the call raises an error

