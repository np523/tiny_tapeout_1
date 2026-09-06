#!/usr/bin/env bash
# Standalone per-module area measurement: synthesizes ONE .sv file in
# isolation (flattened, mapped to the sky130_fd_sc_hd tt corner) and prints
# yosys's `stat -liberty` report, so you can measure a module's real silicon
# cost without running a full chip harden.
#
# Usage: scripts/synth_area.sh path/to/module.sv [top_module_name]
# (top_module_name defaults to the file's basename without extension)

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 path/to/module.sv [top_module_name]" >&2
    exit 1
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Accept a path relative to the current directory, or relative to the repo
# root (so `scripts/synth_area.sh src/foo.sv` works from anywhere).
if [ -f "$1" ]; then
    SRC_FILE=$(realpath "$1")
elif [ -f "$REPO_ROOT/$1" ]; then
    SRC_FILE=$(realpath "$REPO_ROOT/$1")
else
    echo "File not found: $1 (tried ./$1 and $REPO_ROOT/$1)" >&2
    exit 1
fi

TOP=${2:-$(basename "$SRC_FILE" .sv)}

MOUNT_ROOT=/home/np523
case "$SRC_FILE" in
    "$MOUNT_ROOT"/*) ;;
    *) echo "File must be under $MOUNT_ROOT for the docker mount to see it." >&2; exit 1 ;;
esac

LIB=$(find "$MOUNT_ROOT/.ciel/ciel/sky130/versions" -path "*sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" 2>/dev/null | head -1)
if [ -z "$LIB" ]; then
    echo "Could not find sky130_fd_sc_hd tt-corner liberty file under $MOUNT_ROOT/.ciel" >&2
    exit 1
fi

docker run --rm -i --user "$(id -u)":"$(id -g)" \
    -v "$MOUNT_ROOT":"$MOUNT_ROOT" \
    -e PDK_ROOT="$MOUNT_ROOT/.ciel" \
    ghcr.io/librelane/librelane:3.0.5 \
    yosys -p "
        read_verilog -sv $SRC_FILE;
        hierarchy -top $TOP;
        synth -top $TOP -flatten;
        dfflibmap -liberty $LIB;
        abc -liberty $LIB;
        opt_clean;
        stat -liberty $LIB
    "
