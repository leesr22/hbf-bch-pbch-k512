# Verification report

## Functional simulation

| Design | Test | Result | Evidence |
|---|---|---|---|
| BCH Encoder | 64 reference messages/codewords | PASS, bit-exact | `sim/logs/bch_encoder_run.log` |
| BCH Decoder | 64 received words, E=0..6 | PASS, payload/status exact | `sim/logs/bch_decoder_run.log` |
| Gaussian PBCH Encoder | 64 txns, 1,032 rows | PASS, codeword/selector/rank/status exact | `sim/logs/pbch_gauss_run.log` |
| PBCH Decoder | primary 64 | PASS, payload/status exact | `sim/logs/pbch_decoder_primary_run.log` |
| PBCH Decoder | stress 64 including E>t | PASS, payload/status exact | `sim/logs/pbch_decoder_stress_run.log` |
| PBCH Decoder | stress + randomized backpressure | PASS | `sim/logs/pbch_decoder_stress_bp_run.log` |

## Throughput

- BCH Encoder: 4,096 transactions, H-II=C-II=5.
- BCH Decoder: 128 continuous exactly-t transactions, H-II=C-II=13.
- PBCH Decoder: 128 continuous exactly-t transactions, H-II=C-II=12.
- Gaussian PBCH Encoder: 128 transactions per controlled U point.

## Synthesis qualification

Every reported PPA row has a complete mapped netlist and area/timing reports.
The Gaussian Encoder uses the exact 340-MHz mapped netlist re-analysed at
320 MHz; this is labelled mapped-netlist operating-point STA, not a new
320-MHz area-optimized synthesis. Setup slack is +0.184462 ns.

Ideal-clock hold reports contain negative slack. No false path or multicycle
exception was invented to hide it. These are pre-layout logic-synthesis results,
not CTS/P&R signoff.
