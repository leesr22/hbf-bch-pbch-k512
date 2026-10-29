#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 ]]; then
    echo "usage: run.sh TOP FILELIST PERIOD_NS RUN_ID" >&2
    exit 2
fi
project_root=$(cd "$(dirname "$0")/../.." && pwd)
run_top=$1
run_filelist=$2
run_period=$3
run_id=$4
run_out="$project_root/syn/runs/$run_id"
if [[ -e "$run_out/status.txt" ]]; then
    echo "completed run exists: $run_out" >&2
    exit 3
fi
mkdir -p "$run_out"
export CLEAN_ROOT="$project_root"
export CLEAN_TOP="$run_top"
export CLEAN_FILELIST="$project_root/$run_filelist"
export CLEAN_OUTDIR="$run_out"
export CLEAN_PERIOD="$run_period"
export CLEAN_LIBRARY=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db
flock /tmp/hbf_umc28_dc.global.lock \
    /usr/synopsys/syn/Q-2019.12-SP5-5/bin/dc_shell-xg-t \
    -f "$project_root/syn/scripts/synth.tcl" \
    -output_log_file "$run_out/compile.log"
