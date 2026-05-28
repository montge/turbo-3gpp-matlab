/-!
# Constituent encoder termination (TS36.212 §5.1.3.2.2)

The turbo constituent encoder is a recursive convolutional code with three
memory elements `(s1, s2, s3)`. After the K systematic bits have been
clocked in, the standard appends **three termination steps** that drive the
shift register back to the all-zero state regardless of the prior state.

A termination step is:

```
s1' = 0     -- zero is forced into the input
s2' = s1
s3' = s2
```

after which `s1 := s1'`, `s2 := s2'`, `s3 := s3'`. The lemma below proves
that three consecutive termination steps, applied to any starting state,
land in `(false, false, false)`.

The state lives in `Bool × Bool × Bool` (so there are only 8 starting
states); the lemma is therefore directly decidable by `decide`, without
any external library. Matches the encoder loop in `constituent_encoder.m`
lines 58-74.
-/

namespace Turbo3gpp.Encoder

/-- One trellis-termination step: zero into `s1`, shift the register. -/
@[inline] def terminationStep (s : Bool × Bool × Bool) : Bool × Bool × Bool :=
  let (s1, s2, _s3) := s
  (false, s1, s2)

/-- Apply three consecutive termination steps. -/
@[inline] def applyTermination (s : Bool × Bool × Bool) : Bool × Bool × Bool :=
  terminationStep (terminationStep (terminationStep s))

/-- Three termination steps drive the encoder to the all-zero state from
    every starting state. The state has 8 elements so the universal is
    discharged by `decide` once destructed into three boolean components. -/
theorem termination_reaches_zero_state :
    ∀ s1 s2 s3 : Bool, applyTermination (s1, s2, s3) = (false, false, false) := by
  decide

/-- The same fact stated as a `#eval`-style truth table for human inspection. -/
example : applyTermination (true,  true,  true)  = (false, false, false) := by decide
example : applyTermination (true,  false, true)  = (false, false, false) := by decide
example : applyTermination (false, true,  false) = (false, false, false) := by decide
example : applyTermination (false, false, false) = (false, false, false) := by decide

end Turbo3gpp.Encoder
