# Reproduction

Run from `/home/leesr0222/hbf-bch-pbch-final-k512`.

## Functional and throughput simulation

```bash
sim/scripts/run.sh all
```

Individual targets are `bch_enc`, `bch_enc_tp`, `bch_dec`, `bch_dec_tp`,
`pbch_enc`, `pbch_enc_u0`, `pbch_enc_u1`, `pbch_enc_u4`, `pbch_enc_u20`,
`pbch_dec`, and `pbch_dec_tp`.

## Synthesis

```bash
syn/scripts/run.sh bch_encode syn/filelists/bch_encode.f 2.0 NEW_BCH_ENC_RUN
syn/scripts/run.sh bch_decode syn/filelists/bch_decode.f 2.5 NEW_BCH_DEC_RUN
syn/scripts/run.sh pbch_encode_gauss syn/filelists/pbch_encode.f 3.125 NEW_PBCH_ENC_RUN
syn/scripts/run.sh pbch_decode syn/filelists/pbch_decode.f 2.5 NEW_PBCH_DEC_RUN
```

The script uses `/tmp/hbf_umc28_dc.global.lock`, one DC job at a time. The
UMC28 library is referenced at the approved shared-server path and is not
included in this package.

The copied PBCH Encoder PPA is the original 340-MHz mapped netlist qualified by
STA at 320 MHz. The curated Gaussian-only source is functionally equivalent but
must receive a new run ID if a source-identical new netlist is required.

