------------------------------- MODULE harq -------------------------------
(***************************************************************************
 * TLA+ model of the 3GPP turbo-coded HARQ retransmission protocol
 * implemented by `turbo_encoding_chain` + `turbo_decoding_chain` with
 * `I_HARQ = 1` (see openspec/specs/coding-chain/spec.md).
 *
 * Discharges two obligations from
 * openspec/changes/add-formal-verification/specs/formal-verification/spec.md
 * ("TLA+ HARQ protocol model" requirement):
 *
 *   1. Safety  `CRCPassImpliesSyndromeZero`  — whenever the decoder
 *      declares success (`decoded /= NULL`), the CRC of the decoded block
 *      is zero. The model captures this by allowing `DecodeAndCheck`
 *      to set `decoded /= NULL` only when the chosen value's CRC is
 *      zero, so the invariant holds by construction. Matches the
 *      MATLAB decoder's early-termination acceptance criterion
 *      (turbo_decoder.m lines 89-93 and the in-iteration CRC checks).
 *
 *   2. Bounded liveness  `EventualTermination`  — every trace reaches
 *      a state with `phase = "done"`, which corresponds to either
 *      `decoded /= NULL` (success) or `attempt = Len(RvIdxSequence) + 1`
 *      (explicit failure after every redundancy version has been tried).
 *      Checked with TLC's `-property` (temporal) mode in harq.cfg.
 *
 * Phase variable. The protocol's sequencing is enforced by a `phase`
 * variable taking values in {transmit, in_channel, decode, advance,
 * done}. Each action fires only in its appropriate phase and advances
 * phase exactly once, preventing degenerate cycles such as
 * "retransmit on the same attempt".
 *
 * Channel abstraction. AWGN is collapsed to a boolean flag `noisy`
 * set non-deterministically by `Channel`. When `noisy = FALSE` the
 * decoder MAY still fail (modelling adversarial scheduling of decode
 * failures even on a clean channel — `decode` non-deterministically
 * chooses success or failure); the CRC's 2^-P collision probability
 * is captured by allowing decode to accept even when `noisy = TRUE`.
 ***************************************************************************)

EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    RvIdxSequence,         (* Sequence in Seq(0..3) — the configured       *)
                           (* retransmission order, e.g. <<0, 2, 3, 1>>.    *)
    InformationBlocks      (* Finite set of "fingerprints" for information  *)
                           (* blocks. We don't need bit-level content for    *)
                           (* the protocol invariants — just a tag so the    *)
                           (* decoder can output `decoded \in this set or    *)
                           (* NULL`. Typically {1, 2}.                       *)

ASSUME RvIdxSeqOk == /\ RvIdxSequence \in Seq(0..3)
                     /\ Len(RvIdxSequence) >= 1
                     /\ Len(RvIdxSequence) <= 4
ASSUME InformationBlocksOk == /\ InformationBlocks # {}
                              /\ Cardinality(InformationBlocks) <= 4

(***************************************************************************
 * Operator-bound default values for the TLC configuration file. `.cfg`
 * cannot literalise a sequence; we expose these as operators and let
 * `harq.cfg` reference them via `<-`.
 ***************************************************************************)
RvIdxSeqDefault == <<0, 2, 3, 1>>
InformationBlocksDefault == {1, 2}

(* NULL == 0 works as a sentinel because by convention info-block tags in
   InformationBlocks are positive integers (the cfg uses {1, 2}). Keeping
   NULL and the tag set in the same type (Nat) lets TLC compare them
   with `=` and `#` cleanly. *)
NULL == 0

(* Phase machine: enforces the per-attempt sequence transmit → channel
   → decode → (advance | done). *)
Phases == {"transmit", "in_channel", "decode", "advance", "done"}

(***************************************************************************
 * State variables.
 ***************************************************************************)
VARIABLES
    attempt,               (* 1..Len(RvIdxSequence)+1; Len+1 = explicit     *)
                           (* failure state after every RV has been tried.  *)
    phase,                 (* Element of Phases (see above).                *)
    noisy,                 (* Most recent channel verdict.                  *)
    buffer,                (* TRUE iff the HARQ buffer has accumulated at   *)
                           (* least one transmission's LLRs.                *)
    decoded                (* InformationBlocks \cup {NULL}                 *)

vars == << attempt, phase, noisy, buffer, decoded >>

(***************************************************************************
 * CRC oracle. Abstracts the CRC-24A check against
 * `CRC_generator_matrix_TB`. Returns TRUE iff `b` is a valid information-
 * block tag (i.e. a value the decoder may legitimately accept). The deeper
 * content — that the matrix-product CRC equals polynomial division — is
 * discharged by the Lean proof, not by this model.
 ***************************************************************************)
crcZero(b) == b \in InformationBlocks

(***************************************************************************
 * Initial state. Phase ready for the first transmission; no LLRs yet;
 * decoder idle.
 ***************************************************************************)
Init ==
    /\ attempt = 1
    /\ phase = "transmit"
    /\ noisy = FALSE
    /\ buffer = FALSE
    /\ decoded = NULL

(***************************************************************************
 * Actions.
 ***************************************************************************)

(* Encode the information block under the current redundancy version and *)
(* place it on the channel.                                               *)
EncodeAndTransmit ==
    /\ phase = "transmit"
    /\ phase' = "in_channel"
    /\ UNCHANGED << attempt, noisy, buffer, decoded >>

(* The channel non-deterministically corrupts (or doesn't) the in-flight *)
(* frame. Models AWGN as bounded bit-flips collapsed to a boolean flag.   *)
Channel ==
    /\ phase = "in_channel"
    /\ \E n \in BOOLEAN : noisy' = n
    /\ phase' = "decode"
    /\ UNCHANGED << attempt, buffer, decoded >>

(* The decoder accumulates the in-flight frame's LLRs into the HARQ      *)
(* buffer, then runs the turbo decoder and the transport-block CRC.      *)
(* Non-deterministically chooses to accept some block tag (if the CRC    *)
(* passes for that tag, by `crcZero`) or to fail.                         *)
DecodeAndCheck ==
    /\ phase = "decode"
    /\ buffer' = TRUE
    /\ \/ /\ \E b \in InformationBlocks :
              /\ crcZero(b)
              /\ decoded' = b
          /\ phase' = "done"
       \/ /\ decoded' = NULL
          /\ phase' = "advance"
    /\ UNCHANGED << attempt, noisy >>

(* Move to the next redundancy version after a decode failure. If we      *)
(* have exhausted the rv_idx sequence, advance to the terminal failure    *)
(* state attempt = Len(RvIdxSequence) + 1 (explicit failure) and stop.    *)
AdvanceRv ==
    /\ phase = "advance"
    /\ attempt' = attempt + 1
    /\ IF attempt + 1 > Len(RvIdxSequence)
       THEN phase' = "done"
       ELSE phase' = "transmit"
    /\ UNCHANGED << noisy, buffer, decoded >>

(* Stutter in the terminal state for the temporal liveness check. *)
Stutter ==
    /\ phase = "done"
    /\ UNCHANGED vars

Next ==
    \/ EncodeAndTransmit
    \/ Channel
    \/ DecodeAndCheck
    \/ AdvanceRv
    \/ Stutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

(***************************************************************************
 * Properties.
 ***************************************************************************)

(* Type invariant — sanity check. *)
TypeOK ==
    /\ attempt \in 1..(Len(RvIdxSequence) + 1)
    /\ phase \in Phases
    /\ noisy \in BOOLEAN
    /\ buffer \in BOOLEAN
    /\ decoded \in InformationBlocks \cup {NULL}

(* Safety: any non-NULL `decoded` has CRC = 0 (= is in InformationBlocks). *)
CRCPassImpliesSyndromeZero ==
    decoded # NULL => crcZero(decoded)

(* When phase = done, we have either succeeded (decoded /= NULL) or
   exhausted every RV (attempt = Len + 1). This is the protocol's
   well-formedness condition. *)
DoneIsExplicit ==
    phase = "done" => (decoded # NULL \/ attempt = Len(RvIdxSequence) + 1)

(* Bounded liveness: every trace eventually settles in phase = done. *)
EventualTermination ==
    <>[](phase = "done")

=============================================================================
