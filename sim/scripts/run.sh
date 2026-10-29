#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
mkdir -p sim/build sim/new_logs

vcs_bin=/usr/synopsys/vcs/R-2020.12-SP1-1/bin/vcs
common=(+warn=noLNX_OS_VERUN +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed +incdir+.)

run_vcs() {
    local name=$1 top=$2
    shift 2
    "$vcs_bin" "${common[@]}" -top "$top" -Mdir="sim/build/csrc_$name" \
        -o "sim/build/simv_$name" "$@" -l "sim/new_logs/${name}_compile.log"
    "sim/build/simv_$name" -l "sim/new_logs/${name}_run.log"
}

run_one() {
    case "$1" in
        bch_enc)
            run_vcs bch_enc tb_bch_encoder_w128 -f syn/filelists/bch_encode.f \
                sim/tb/bch_compat.sv sim/tb/tb_bch_encoder_w128.sv ;;
        bch_enc_tp)
            run_vcs bch_enc_tp tb_bch_encoder_w128_throughput -f syn/filelists/bch_encode.f \
                sim/tb/bch_compat.sv sim/tb/tb_bch_encoder_w128_throughput.sv ;;
        bch_dec)
            run_vcs bch_dec tb_paper_bch_decoder -f syn/filelists/bch_decode.f \
                sim/tb/bch_compat.sv sim/tb/tb_paper_bch_decoder.sv ;;
        bch_dec_tp)
            run_vcs bch_dec_tp tb_decoder_throughput -f syn/filelists/bch_decode.f \
                sim/tb/bch_compat.sv sim/tb/tb_decoder_throughput.sv ;;
        pbch_enc)
            run_vcs pbch_enc pbch_encode_tb -f syn/filelists/pbch_encode.f \
                sim/tb/pbch_encode_tb.sv ;;
        pbch_enc_u0|pbch_enc_u1|pbch_enc_u4|pbch_enc_u20)
            local def
            case "$1" in
                pbch_enc_u0) def=U0 ;;
                pbch_enc_u1) def=U1 ;;
                pbch_enc_u4) def=U4 ;;
                pbch_enc_u20) def=U20 ;;
            esac
            run_vcs "$1" pbch_encode_throughput_tb "+define+$def" \
                -f syn/filelists/pbch_encode.f sim/tb/pbch_encode_throughput_tb.sv ;;
        pbch_dec)
            run_vcs pbch_dec tb_paper_pbch_decoder +define+PBCH_MODE +define+DECOUPLED \
                +define+PIPE_OUTPUT2 -f syn/filelists/pbch_decode.f \
                sim/tb/pbch_decode_compat.sv sim/tb/tb_paper_pbch_decoder.sv ;;
        pbch_dec_tp)
            run_vcs pbch_dec_tp tb_decoder_throughput +define+PBCH_MODE +define+DECOUPLED \
                +define+PIPE_OUTPUT2 -f syn/filelists/pbch_decode.f \
                sim/tb/pbch_decode_compat.sv sim/tb/tb_decoder_throughput.sv ;;
        *) echo "unknown target: $1" >&2; exit 2 ;;
    esac
}

target=${1:-all}
if [[ "$target" == all ]]; then
    for item in bch_enc bch_enc_tp bch_dec bch_dec_tp pbch_enc \
        pbch_enc_u0 pbch_enc_u1 pbch_enc_u4 pbch_enc_u20 pbch_dec pbch_dec_tp; do
        run_one "$item"
    done
else
    run_one "$target"
fi
