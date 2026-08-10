# Debugging a 12-bit DVI Pmod on the iCEBreaker

A record of bringing up a hand-soldered 1BitSquared 12-bit DVI Pmod on an iCEBreaker V1.1a, and the fault that stopped it. The video output was not working.

**Hardware:** iCEBreaker V1.1a (iCE40UP5K, SG48), 1BitSquared 12-bit DVI Pmod
(TFP410), right-angle headers soldered by hand.
**Toolchain:** OSS CAD Suite on Windows — Yosys, nextpnr-ice40, icetime, icepack,
iceprog.
**Reference design:** [ProjectF](https://github.com/projf/projf-explore) `square`
demo from the Beginning FPGA Graphics series.

---

## Starting position

A blinking LED already worked on this board, which established more than it appears to. Board power, the 12 MHz oscillator, the FTDI programming path, and the entire synthesis-to-flash toolchain were all known-good before the DVI work began.

That left exactly three new variables for a video test: the Pmod board itself,
the hand-soldered joints, and the DVI-specific HDL. Any failure had to be in one
of those three. Holding onto that boundary mattered later, because it kept the
search space from expanding every time something looked strange.

## Build

`square` was chosen over a flat colour fill deliberately. A white square on a
blue field exercises specific colour bits rather than all of them at once, so a
stuck or floating data line shows up as a visibly wrong tint instead of hiding
inside a uniform screen.

`make` isn't in the Windows OSS CAD Suite bundle, so the pipeline was run by
hand. Reading the ProjectF Makefile rather than assuming its contents caught two
things: the support module is `simple_480p.sv`, not the `display_480p.sv` the
tutorial prose suggests, and the synthesis flags include `-device u`, which
targets the iCE40 Ultra family specifically. Omitting that flag still
synthesises, but maps to primitives that don't match the actual silicon.

```
yosys -ql square-yosys.log -p "synth_ice40 -abc9 -device u -top top_square -json square.json" top_square.sv ../../../lib/clock/ice40/clock_480p.sv ../simple_480p.sv
nextpnr-ice40 --up5k --package sg48 --json square.json --pcf icebreaker.pcf --asc square.asc
icetime -d up5k -mtr square.rpt square.asc
icepack square.asc square.bin
iceprog square.bin
```

Every stage passed. All sixteen DVI pins mapped to real package pins with no
conflicts, the PLL constrained to 25.1 MHz from the 12 MHz input, and timing
closed at 44.74 MHz against a 25.14 MHz requirement — nearly 2x margin. That
number turned out to be useful: it meant no subsequent failure could be blamed
on marginal timing, which removed a whole category of suspect.

A programming failure interrupted this — `iceprog` reported it couldn't find the
FTDI device. Windows had bound the default serial driver, putting the board on
COM4 instead of leaving it available for WinUSB. Zadig on Interface 0 fixed it.
Worth noting the driver binding is per-port, so moving the board to a different
USB socket can require redoing this. COM4 remaining afterwards is correct — the
FTDI chip exposes two interfaces and only Interface 0 needs WinUSB.

## First result: no signal

Nothing on a TV, nothing on a monitor. The monitor cycled its inputs, which is
what monitors do when no valid signal is present on the selected one.

Two displays failing the same way largely ruled out a display-side quirk. That
mattered because a TV rather than a monitor was the first thing tried, and TVs
are genuinely fussier about DVI — the Pmod emits DVI-D over an HDMI-compatible
connector, with no audio and no HDMI data islands, and some televisions handle
that worse than any computer monitor would.

A locked-but-blank screen and a no-signal screen mean different things. No signal
implies the TFP410 never received a usable clock or sync, because without those
it can't transmit anything at all. That pointed at the clock, the sync lines, or
power — not at the colour data.

## Electrical checks

Power first, since an unpowered TFP410 produces exactly this symptom regardless
of how good every other connection is. 3.29 V across the Pmod's power and ground
pins on both connectors. Ruled out.

Then continuity, pin by pin, from each iCEBreaker header pin through to the
corresponding Pmod pad. This sidesteps needing to know which signal sits where —
it just tests whether every physical connection goes all the way through. The
four that matter most for a no-signal fault are the clock and the three control
lines, since a single break in any of them kills the whole image. All continuous.

Then the reverse test: continuity *between* neighbouring pins, where silence is
the correct answer. This is the check the first sweep misses. A pin bridged to
ground is stuck low permanently, and a far-end continuity test passes cleanly on
a shorted pin — the connection is there, it's just also connected to something
it shouldn't be.

**This produced the most instructive result of the whole investigation.** With
the board powered, several neighbouring pins showed continuity. With power
removed, none did.

The powered readings were false. A continuity tester injects a small current and
expects to measure passive copper. On a live circuit it also measures whatever
the silicon is doing — internal pull-ups and pull-downs, ESD protection diodes,
active driver outputs — and those create leakage paths that read as connections
between pins with no physical bridge between them. Continuity testing on a
powered circuit produces false positives as a matter of course.

The unpowered result is the trustworthy one, and it was clean. No bridges.

At that point the multimeter had said everything it could. Power good, no opens,
no bridges. Nothing left to measure by DC.

## Making a 25 MHz problem visible

The remaining problem was one of observability. Every symptom was downstream of a
25 MHz pixel clock, which a multimeter cannot see, and three distinct failure
layers were bundled into one opaque result: the PLL might not be locking, the
sync timing might be wrong, or the physical pin path might be broken. No
available instrument could separate them.

So the design was changed to fit the instrument. A minimal bitstream, no PLL, no
external modules, driving the pins from a counter divided down off the 12 MHz
oscillator:

```systemverilog
module top_pin_test (
    input  wire clk_12m,
    output wire dvi_clk,
    output wire dvi_hsync,
    output wire dvi_vsync,
    output wire dvi_de,
    output wire [3:0] dvi_r,
    output wire [3:0] dvi_g,
    output wire [3:0] dvi_b
);

    reg [22:0] counter;
    always @(posedge clk_12m) counter <= counter + 1'b1;

    wire slow = counter[22];  // state change every ~0.35 s

    assign dvi_clk   = slow;
    assign dvi_hsync = slow;
    assign dvi_vsync = slow;
    assign dvi_de    = slow;
    assign dvi_r     = {4{slow}};
    assign dvi_g     = 4'b0000;
    assign dvi_b     = 4'b0000;

endmodule
```

`counter[22]` changes state every 2^22 / 12,000,000 ≈ 0.35 s. Slow enough for a
multimeter in DC volts to follow directly, or an LED to show visually.

The green and blue pins are held at zero deliberately. They're a control: if any
of them toggles, there's a bridge to a driven line, which is a fault the test
detects for free. Driving every pin identically would have thrown that away.

This isolates one variable. It says nothing about the PLL or DVI timing, and it
isn't supposed to. It answers only: does a signal this design explicitly drives
physically arrive at that pin.

**Result:** the clock, both syncs, and all four red bits toggled cleanly. `de`
did not.

One pin behaving differently from eight others driven off the same net is about
as clean a localisation as blind debugging produces. There is no design reason
for `de` to differ, so the cause had to be physical and specific to that net.

## The `de` fault

`de` — data enable — tells the TFP410 which pixels are active. Held inactive, the
chip transmits blanking, and a monitor locks onto valid sync and renders black.
Sync working, pixels disabled.

What followed was several rounds of rework, each changing the symptom without
resolving it: stuck high, then stuck low on the Pmod side while reading high on
the iCEBreaker side, then stuck high again. The differing readings across the
joint were themselves diagnostic — two points at different potentials can't be
connected, so at one stage the bridge had been cleared and the connection broken
in the same operation.

Two errors are worth recording, because catching them changed the conclusions.

**A misidentified pin.** Several iCEBreaker-side measurements were taken on
`dvi_b[0]` rather than `dvi_de` — position 3 instead of position 9. `b[0]` is
tied low by the test design, so "stuck low" there was correct behaviour being
read as a fault. An entire theory about a damaged output driver had been built on
that data and had to be discarded. Every affected measurement was re-run.

**A misread measurement.** A reading oscillating between 3.28 V and 3.29 V was
briefly taken as a toggle. It's a steady rail with last-digit meter noise. A real
toggle swings between roughly 0 V and 3.3 V.

**The control measurement that settled it.** `de` read ~32.5 Ω to the 3.3 V rail,
symmetric in both probe orientations. The question was whether that number meant
anything, and the way to find out was to measure a pin already known to be
healthy. `hsync` — which toggled correctly, so healthy by definition — read
~5 MΩ to the same rail.

That comparison is what made the 32.5 Ω meaningful. Without it the number is
unanchored: it could have been what any I/O pin reads to that rail on an
unpowered board, in which case there was no fault at all. With it, the reading is
specific to one net, on one board, against a known baseline.

Symmetry across probe orientations matters too. Semiconductor junctions conduct
one way and not the other, so an asymmetric reading would have indicated the
chip's internal ESD structures rather than a defect. Symmetric points at a
resistance — a resistor, a bridge, or a partial contact.

## Where it ended

32.5 Ω is a strange value for a solder bridge. Actual solder reads under an ohm.
That suggested contamination — flux residue or a fine whisker — rather than a
metal bridge, and would also explain why aggressive desoldering left the value
unchanged: heat doesn't remove residue.

Isopropyl and a brush on the header area. Still 32.5 Ω.

**Root cause undetermined.** The evidence supports two explanations and does not
distinguish between them:

1. A bridge or whisker under the right-angle header, inaccessible without
   desoldering it entirely. Header adjacency isn't PCB adjacency — traces fan
   out, change layers through vias, and can pass within thousandths of an inch of
   each other in places unrelated to connector pin order. `de` at position 9 and
   VCC at position 12 look far apart at the connector and needn't be on the
   board.
2. A damaged output driver on FPGA pin 32. There was a period where that pin was
   driven against a low-resistance path while powered, which is the stress that
   causes this. An internally damaged driver would read symmetric, wouldn't clean
   off, wouldn't be visible, and would be specific to one pin while its
   neighbours read 5 MΩ.

Both fit every measurement. Distinguishing them needs the header removed or the
board under a microscope, and further attempts risked turning one bad pin into a
lifted pad. `dvi_de` can't be reassigned — the Pmod's wiring is fixed and the
constraints file has to match it.

Stopped here.

## What the process was worth

- **Blink before the hard thing.** Re-flashing the known-good design after
  extensive rework confirmed the board still configured, programmed, and drove
  I/O. Without it, a later failure would have been ambiguous between the original
  fault and collateral damage.
- **Continuity on powered circuits lies.** Active silicon creates leakage paths
  that read as bridges. Only the unpowered measurement is trustworthy.
- **Match the instrument to the problem.** A 25 MHz signal is invisible to a
  multimeter. Rewriting the design to produce a 0.35 s toggle made the physical
  layer measurable with the tool available.
- **Isolate one layer at a time.** The pin test deliberately answers less than
  the full question. Bypassing the PLL and DVI timing is what makes its result
  unambiguous.
- **Controls make readings mean something.** 32.5 Ω is a number. 32.5 Ω against
  5 MΩ on a known-good pin is a finding.
- **Check the probe orientation.** Symmetric and asymmetric readings point at
  different physical causes.
- **Verify which pin you're on.** A six-position error produced a confident,
  entirely wrong theory.
- **Know when the measurements have stopped informing.** Past a certain point the
  DC readings were being reinterpreted rather than adding evidence.

## Toolchain notes

- Launch OSS CAD Suite via `start.bat`. Running `environment.bat` inside an
  existing PowerShell session doesn't configure PATH correctly. `start.bat` opens
  a `cmd.exe` session with everything set.
- `make` isn't in the Windows bundle. Run the pipeline manually.
- After the board re-enumerates, Windows may reclaim it with the default FTDI
  serial driver. Re-apply WinUSB to Interface 0 with Zadig. The driver binding is
  per-port.
- Keep the toolchain and your projects in sibling directories. Working inside
  `oss-cad-suite` risks losing work when the toolchain is updated or re-extracted.
