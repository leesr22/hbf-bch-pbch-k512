#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 ]]; then
    echo "usage: sta.sh DDC PERIOD_NS OUTDIR LOG" >&2
    exit 2
fi
project_root=$(cd "$(dirname "$0")/../.." && pwd)
export STA_DDC="$project_root/$1"
export STA_PERIOD="$2"
export STA_OUTDIR="$project_root/$3"
export STA_LIBRARY=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db
flock /tmp/hbf_umc28_dc.global.lock \
    /usr/synopsys/syn/Q-2019.12-SP5-5/bin/dc_shell-xg-t \
    -f "$project_root/syn/scripts/sta.tcl" \
    -output_log_file "$project_root/$4"
