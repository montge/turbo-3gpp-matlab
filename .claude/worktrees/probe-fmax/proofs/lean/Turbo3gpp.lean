import Turbo3gpp.CRC
import Turbo3gpp.Interleaver
import Turbo3gpp.Encoder

/-!
# turbo-3gpp-matlab — Lean 4 proofs (entry point)

The actual theorems live in:

* `Turbo3gpp.CRC`            — CRC matrix ≡ polynomial division
* `Turbo3gpp.Interleaver`    — QPP bijection over the 188 supported K
* `Turbo3gpp.Encoder`        — constituent encoder termination
-/
