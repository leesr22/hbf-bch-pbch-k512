# PPA and throughput method

For 512 payload bits and measured steady-state completion interval `CII`:

```text
BW_engine_GBps = 64 * f_MHz / (1000 * CII)
N_engine        = ceil(3072 / BW_engine_GBps)
A_replicated    = N_engine * A_engine / 1e6   [mm^2]
```

The number of BCH component codewords per 4096-bit block is not multiplied
again. The target already specifies payload bytes per second.

For variable-latency Encoder workloads both mean C-II capacity and maximum
observed interval projections are preserved in `candidate_matrix.csv`. Neither
is claimed as an all-input worst-case guarantee. `U=0/1/4/20` are controlled
service workloads, not probabilities.

Area is UMC28 logic cell area at SSGWC0P9V125C. Constraints are common:

- setup uncertainty: 0.20 ns
- input delay: 0.40 ns
- output delay: 0.40 ns
- selected setup margin: at least +0.15 ns

The BCH Encoder report also contains ideal-clock hold violations. Hold status is
outside the selection rule requested here but is disclosed; no row is presented
as physical signoff.

## Why PBCH Decoder is smaller than BCH Decoder here

PBCH adds selector FIFO and recovery (3,340.176 µm² combined), but its parent
correction capability is t=4 rather than t=6. The parent correction hierarchy
is 8,310.624 µm² versus 12,310.200 µm² for BCH. The correction saving exceeds
recovery overhead, producing a smaller PBCH Decoder.

## Why full PBCH overhead is still large

The Encoder must solve a data-dependent masking problem and reread the message.
Even the selected Solver is 2,628.696 µm², and defect rows extend C-II. Under
an Encoder target of 3072 GB/s, this causes many replicas. Lower real write
traffic may change system provisioning, but that is a different comparison and
was not substituted into this result.

