# Research and implementation sources

Sources were used to select architectural ideas, not to import unverified code
or performance numbers.

1. Yongjune Kim and B. V. K. Vijaya Kumar, *Coding for Memory with Stuck-at
   Defects*, arXiv:1304.4821. The two-step PLBC encoding/fallback distinction
   motivates preserving physical-order fallback rather than treating every
   `U<=ell` set as maskable. <https://arxiv.org/abs/1304.4821>
2. Yongjune Kim and B. V. K. Vijaya Kumar, *Redundancy Allocation of
   Partitioned Linear Block Codes*, arXiv:1305.3289. This supports keeping
   masking and correction redundancy separate. <https://arxiv.org/abs/1305.3289>
3. *Ultra-fast-scalable BCH decoder with efficient-Extended Fast Chien Search*,
   IEEE document 5564592. This was consulted for parallel/structured Chien
   search; the present RTL uses its own verified constants and bit ordering.
   <https://ieeexplore.ieee.org/document/5564592/>
4. Russ Dill, `bch_verilog`, GPL-licensed open-source BCH implementation. Its
   decomposition into encoder, syndrome, key-equation and Chien blocks was used
   as an architectural cross-check; no source was copied into this project.
   <https://github.com/russdill/bch_verilog>

Early-termination and aggressive no-error bypass ideas were not used for the
provisioning winner because the common Decoder workload is continuous exactly-t
correction. A no-error-biased workload would make the hardware comparison look
better without improving the required corrected-payload service rate.

