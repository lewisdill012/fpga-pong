# iCEBreaker FPGA

Learning the open-source iCE40 toolchain on an iCEBreaker V1.1a, working toward
FPGA Pong. Includes a detailed hardware debugging log.

**Hardware:** iCEBreaker V1.1a — Lattice iCE40UP5K, SG48 package
**Toolchain:** OSS CAD Suite on Windows — Yosys, nextpnr-ice40, icetime, icepack,
iceprog
**Reference:** [ProjectF](https://github.com/projf/projf-explore) tutorial series

---

## Contents

### `blink/`

The first working design. Establishes that board power, the 12 MHz oscillator,
the FTDI programming path, and the full synthesis-to-flash toolchain are all
functional. Small, but it's the baseline every later result is measured against.

### `pin-test/`

A diagnostic bitstream written to debug a DVI Pmod fault. No PLL, no external
modules — just a counter dividing the 12 MHz oscillator down to a ~0.35 s toggle
driven onto the DVI control and data pins.

The problem it solves is observability. The real design depends on a 25 MHz pixel
clock, which a multimeter cannot see, and it bundles three failure layers into one
opaque symptom: the PLL might not be locking, the sync timing might be wrong, or a
physical pin path might be broken. A 0.35 s toggle is slow enough to read directly
on a multimeter in DC volts, and it tests only the last of those three.

The green and blue pins are held at zero as a control. If any of them toggles,
there's a bridge to a driven line.

### `docs/dvi-pmod-debug.md`

The full debugging log for the DVI Pmod bring-up. Power verification, continuity
sweeps, the false positives that come from testing powered circuits, the custom
diagnostic bitstream, control measurements against a known-good pin, two of my own
errors that produced wrong conclusions, and where the investigation stopped.

The video output never worked. The fault was isolated to a single net — `dvi_de`
on FPGA pin 32 — but its root cause was not definitively established. The log
records that honestly rather than picking a conclusion the evidence doesn't
support.

---

## Building

Windows note: `make` isn't included in the OSS CAD Suite bundle, so the pipeline
runs manually. Launch the environment via `start.bat` rather than running
`environment.bat` in an existing shell.

```
yosys -p "synth_ice40 -abc9 -device u -top top_pin_test -json test.json" top_pin_test.sv
nextpnr-ice40 --up5k --package sg48 --json test.json --pcf icebreaker.pcf --asc test.asc
icepack test.asc test.bin
iceprog test.bin
```

`-device u` targets the iCE40 Ultra family. Omitting it still synthesises, but
maps to primitives that don't match the UP5K silicon.

## Status

Toolchain working. Blink verified. DVI output blocked by the hardware fault
documented in `docs/`. Pong requires video, so it's pending a replacement board.
