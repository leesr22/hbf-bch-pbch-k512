# Architecture

## Common code parameters

- BCH: `(n,k,r,t)=(572,512,60,6)`
- PBCH: `(n,k,ell,r,t)=(572,512,20,40,4)`
- PBCH parent BCH information length: `k+ell=532`
- Storage order: eight 64-bit message beats followed by one 60-valid-bit beat.

All generator, shortening and bit-order constants come from
`rtl/generated/constants.svh`.  They are elaboration constants/XOR logic, not
runtime coefficient RAMs.

## BCH

`bch_encode` is a 128-bit systematic parity LFSR wrapper. `bch_decode` keeps the
decoder boundary simple while the implementation is explicitly separated into:

1. `syndrome_core`
2. `bm_core`
3. `chien_core`
4. `decode_core` coordination
5. `replay_core` and `message_stream`

The final public files are 28 and 48 lines; algorithms remain in small reusable
modules rather than a monolithic top.

## PBCH Encoder

The common Encoder has two lightweight contexts. Each context keeps 40 parity
bits, 20 selector bits, rank/status, order and tag. The original 512-bit message
is not copied into the core.

1. The first message traversal computes base parity.
2. For each defect, the source cache supplies the addressed message bit when
   the position belongs to the message portion.
3. A Solver consumes one `(row,rhs)` constraint at a time.
4. After `d` is known, the source cache is reread sequentially. Constant XOR
   logic applies `G0*d` while the codeword is emitted.

### Mask Solver: Gaussian

`mask_gauss` stores only 20 pivot rows of 21 bits including RHS. A received row
is reduced in one combinational pass and accepted every two cycles. A
contradictory dependent row is left unmasked, preserving physical-order
fallback. Free variables are fixed to zero. The state size and time scale with
`ell`, not a full `n x ell` augmented matrix.

## PBCH Decoder

The decoder is not coupled to the masking Solver. It performs:

1. parent `t=4` syndrome/BM/Chien correction;
2. corrected-word reread;
3. ordered selector FIFO tracking;
4. streaming `message XOR selector-mask` recovery;
5. status-aligned output commit.

The payload is not returned before the parent decoder status is known. No CRC,
oracle error count, or extra post-correction check was added.
