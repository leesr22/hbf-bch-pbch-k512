# Final k512 BCH/PBCH hardware

최종 채택한 k=512 하드웨어만 모은 재현용 폴더다.

| block | selected configuration |
|---|---|
| BCH Encoder | BCH(572,512,t=6), W128 systematic LFSR |
| BCH Decoder | BCH(572,512,t=6), W64 syndrome/BM/Chien/replay |
| PBCH Encoder | PBCH(572,512,ell=20,t=4), W64, ctx2, incremental Gaussian solver |
| PBCH Decoder | PBCH parent BCH(572,532,t=4), selector FIFO and streaming recovery |

`rtl/pbch/encode.sv`는 최종 Gaussian 경로만 남겼다. 비교 후보였던
Table/Hybrid/Direct Solver는 포함하지 않았다. BCH/PBCH 원본 message 또는
received codeword를 보관하는 source cache는 RTL core 밖의 시스템 자원이다.
필요한 포트와 lifetime은 `results/source_cache_contract.csv`에 기록했다.

## Directory

- `rtl/`: 최종 합성 가능 RTL
- `sim/`: golden vectors, testbench, 완료 로그, 재실행 script
- `syn/`: DC scripts/filelists와 네 채택점의 raw report/netlist/DDC
- `results/`: 최종 PPA/throughput와 hierarchy
- `profiles/`: BCH/PBCH code construction manifest
- `docs/`: architecture, 검증 범위, PPA 방법

## Final measured points

| block | MHz | C-II | engine area (um2) | replicated area at 3072 GB/s (mm2) |
|---|---:|---:|---:|---:|
| BCH Encoder | 500 | 5 | 1786.176 | 0.8574 |
| BCH Decoder | 400 | 13 | 16707.936 | 26.0644 |
| PBCH Encoder U=0 | 320 | 10.000 | 8370.600 | 12.5559 |
| PBCH Encoder U=1 | 320 | 11.984 | 8370.600 | 15.0503 |
| PBCH Encoder U=4 | 320 | 14.976 | 8370.600 | 18.8087 |
| PBCH Encoder U=20 | 320 | 44.000 | 8370.600 | 55.2460 |
| PBCH Decoder | 400 | 12 | 14689.416 | 21.1528 |

`U`는 서로 다른 Encoder가 아니라 동일 PBCH Encoder에 입력한 defect constraint
수다. 자연 defect 확률이나 평균 workload를 뜻하지 않는다.

## Reproduce

```bash
cd /home/leesr0222/hbf-bch-pbch-final-k512
sim/scripts/run.sh all
```

Synthesis 재실행은 `docs/REPRODUCE.md`를 따른다. UMC28 library는 사용 권한
때문에 이 폴더에 복사하지 않고 기존 절대 경로를 참조한다.

## Provenance

- source project: `/home/leesr0222/hbf-pbch-clean-k512`
- source commit: `cb3e897aebcb0466fb7701068e23cadaf48b4768`
- copied PPA runs are immutable completed runs from that commit
- curated PBCH Encoder removes elaboration-dead Table/Hybrid branches; selected
  Gaussian datapath and interface are unchanged and are rechecked by simulation

