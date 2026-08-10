#!/bin/sh
## FPGA Pong - build script for the open-source iCE40 toolchain
##
## Usage:
##   ./build.sh          synthesise, place & route, pack
##   ./build.sh prog     build, then flash the board
##   ./build.sh clean    remove build outputs
##
## Requires yosys, nextpnr-ice40, icetime, icepack and iceprog on PATH.
## On Windows, launch the OSS CAD Suite via start.bat and run this from there.

set -e

PROJ=pong
TOP=top_pong
DEVICE=up5k
PACKAGE=sg48
PCF=icebreaker.pcf

## Yosys has no module search path, so every source file is listed here.
SRC="top_pong.v simple_480p.v clock_480p.v debounce.v simple_score.v"

clean() {
    rm -f $PROJ.json $PROJ.asc $PROJ.bin $PROJ.rpt $PROJ-yosys.log
}

build() {
    # Verilog -> netlist of iCE40 primitives
    # -device u targets the UP5K silicon; without it yosys maps to primitives
    # that don't exist on this part
    yosys -ql $PROJ-yosys.log \
        -p "synth_ice40 -abc9 -device u -top $TOP -json $PROJ.json" $SRC

    # netlist + pin constraints -> placed and routed design
    nextpnr-ice40 --$DEVICE --package $PACKAGE \
        --json $PROJ.json --pcf $PCF --asc $PROJ.asc

    # static timing report (informational; nextpnr already checks timing)
    icetime -d $DEVICE -mtr $PROJ.rpt $PROJ.asc

    # -> bitstream
    icepack $PROJ.asc $PROJ.bin
}

case "$1" in
    clean)
        clean
        ;;
    prog)
        build
        iceprog $PROJ.bin
        ;;
    "")
        build
        ;;
    *)
        echo "usage: $0 [prog|clean]" >&2
        exit 1
        ;;
esac