# FPGA Pong

Using the open-source iCE40 toolchain — Yosys, nextpnr, IceStorm — on an iCEBreaker FPGA to create a working recreation of Pong over DVI.

**Hardware:** iCEBreaker V1.1a — Lattice iCE40UP5K, SG48 package, 12-bit DVI Pmod (Pmod 1A/1B)
**Toolchain:** OSS CAD Suite on Windows — Yosys, nextpnr-ice40, icetime, icepack, iceprog

---

## Contents

### `blink/`

Confirms board power, the 12 MHz oscillator, the FTDI programming path, and the full synth -> place-and-route -> pack -> flash pipeline all work end to end before anything else is attempted.

### `pin-test/`

A diagnostic test for bringing up the DVI Pmod independent of the real pixel-clock design. It drives every DVI control and data pin from a ~0.7 Hz divided clock — slow enough to read directly on a multimeter, and it isolates one variable at a time.

The slow toggle here tests if a physical pin path is broken. Green and blue are held at zero as a control — if either toggles, there's a bridge to a driven line.

### `pong/`

The Pong implementation, following ProjectF's design:

| File | Role |
|---|---|
| `top_pong.v` | Top-level FSM (`NEW_GAME → POSITION → READY → PLAY → POINT/END_GAME`), player and AI paddle control, ball physics, scoring, and DVI pixel output. |
| `clock_480p.v` | `SB_PLL40_PAD` instantiation generating the ~25.2 MHz pixel clock from the 12 MHz board oscillator |
| `simple_480p.v` | 640×480 horizontal/vertical sync and timing generator |
| `debounce.v` | Clock-synchronized button debouncer with edge-detected up/down pulses |
| `simple_score.v` | 3×5 bitmap digit renderer for the on-screen score |
| `build.sh` | Manual synth → place-and-route → timing report → pack pipeline |

---

## Building

The Windows OSS CAD Suite bundle doesn't include `make`, so `pong/build.sh` runs the pipeline as discrete commands instead. Launch the toolchain environment via `start.bat` (not `environment.bat` in an existing shell) so the required env vars are set, then:

```sh
./build.sh          # synthesize, place & route, pack
./build.sh prog      # build, then flash the board
./build.sh clean     # remove build outputs
```

`-device u` in the synthesis step targets the iCE40 Ultra family; omitting it still synthesizes, but maps to primitives that don't match the UP5K silicon.

`blink/` currently builds via its `Makefile` — run the same steps manually if `make` isn't on your PATH:

```sh
yosys -p "synth_ice40 -top top -json blink.json" blink.v
nextpnr-ice40 --up5k --package sg48 --json blink.json --pcf blink.pcf --asc blink.asc
icepack blink.asc blink.bin
iceprog blink.bin
```

---

## Acknowledgments

The `pong/` modules are derived from Will Green's [Project F](https://projectf.io)
FPGA tutorials — *Beginning FPGA Graphics* and [*FPGA Pong*](https://projectf.io/posts/fpga-pong/) —
released under the MIT License. Ported to Verilog-2001 and adapted for the
iCEBreaker + 12-bit DVI Pmod. See [LICENSE](LICENSE).