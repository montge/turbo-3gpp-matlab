import Lake
open Lake DSL

-- Lake project for the turbo-3gpp-matlab Lean 4 proofs.
--
-- Three top-level theorems (see proofs/traceability.md):
--   * CRC matrix-product ≡ polynomial division over GF(2) for the four
--     3GPP CRC polynomials (TS36.212 §5.1.1).
--   * QPP interleaver `pi(i) = (f1*i + f2*i²) mod K` is a bijection on
--     `Fin K` for every one of the 188 supported K values
--     (TS36.212 §5.1.3.2.3).
--   * The 3-step trellis termination drives the constituent encoder
--     state register to (0, 0, 0) from any prior state
--     (TS36.212 §5.1.3.2.2).
--
-- We deliberately depend on no external libraries (no mathlib): the QPP
-- and termination proofs are pure `decide`, and the CRC equivalence is
-- a structural induction on `List Bool` provable from Lean's stdlib.
-- That keeps CI cold-build time under a minute.

package «turbo3gpp_proofs» where
  -- Disable native code generation for proof-only modules (faster compile).
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

@[default_target]
lean_lib «Turbo3gpp» where
  -- Default target builds every module under Turbo3gpp/.
  roots := #[`Turbo3gpp]
