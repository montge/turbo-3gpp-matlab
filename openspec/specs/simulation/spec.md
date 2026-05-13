# simulation Specification

## Purpose
TBD - created by archiving change backport-3gpp-turbo-baseline. Update Purpose after archive.
## Requirements
### Requirement: BLER vs SNR simulation driver

The system SHALL provide a `plot_BLER_vs_SNR(A, R, rv_idx_sequence, max_iterations, approx_maxstar, target_block_errors, target_BLER, EsN0_start, EsN0_delta, seed)` driver that:

1. For each information-block length in `A` and each coding rate in `R`, configures a `turbo_encoding_chain` and a `turbo_decoding_chain` with `Q_m = 2` (QPSK), `I_HARQ = 1`, and `iterations = max(max_iterations)`.
2. Modulates encoded bits using QPSK, adds complex AWGN with `N0 = 1 / 10^(EsN0 / 10)`, and demodulates to LLRs.
3. Implements incremental redundancy by encoding/decoding with each `rv_idx` in `rv_idx_sequence` until the transport-block CRC passes or the sequence is exhausted; the decoder buffer is reset between independent transport blocks.
4. Continues simulating each `EsN0` until either `target_block_errors` block errors have accumulated, then advances `EsN0` by `EsN0_delta`, stopping when the BLER drops below `target_BLER`.
5. Persists incremental results to `results/BLER_vs_SNR_<A>_<R>_<retx>_<approx>_<target_errors>_<EsN0_start>_<seed>.txt` with a header row and one row per simulated `EsN0`.
6. Seeds the random number generator from the `seed` argument so two runs with identical arguments produce identical results.

The implementation MAY rely on MATLAB's live graphics (`plot`, `set`, `drawnow`, `axes` with `'YScale','log'`) and is NOT required to run under Octave; the simulation spec only requires the result file format and the encode/decode loop logic.

#### Scenario: Default-rate run records to results directory
- **WHEN** `plot_BLER_vs_SNR(40, 1/3, [0], 8, true, 100, 1e-2, 0, 0.5, 1)` is invoked (under MATLAB)
- **THEN** a file is created at `results/BLER_vs_SNR_40_0.33333_1_1_100_0_1.txt` (with formatting matching `num2str`) containing one row per simulated `EsN0`

#### Scenario: Identical seeds reproduce results
- **WHEN** the driver is invoked twice with identical arguments
- **THEN** the two result files contain identical numerical content

### Requirement: SNR vs A simulation driver

The system SHALL provide a `plot_SNR_vs_A` driver that performs the same encode/decode loop as `plot_BLER_vs_SNR` but sweeps the information-block length `A` for a fixed `target_BLER`, interpolating the `EsN0` that achieves the target BLER for each `A` and writing results to a similarly named file under `results/`.

#### Scenario: Sweep over A
- **WHEN** the driver is invoked with a vector of `A` values
- **THEN** the result file contains one row per `A` value with the interpolated `EsN0` that achieves `target_BLER`

