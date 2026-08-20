# Debugging a 12-bit DVI Pmod on the iCEBreaker

The video output had trouble worked. This is a record of why.

**Hardware:** iCEBreaker V1.1a, 1BitSquared 12-bit DVI Pmod (TFP410), hand-soldered
right-angle headers.

## Starting position
Blink already worked, which confirmed board power, the 12 MHz oscillator, the
FTDI programming path, and the full toolchain. That left three variables: the
Pmod board, the solder joints, and the DVI-specific HDL.

## Build
Used ProjectF's `square` demo rather than a flat fill — a white square on blue
exercises specific color bits, so a stuck line shows as a wrong tint instead of
disappearing into a uniform screen. Timing closed at 44.74 MHz against a
25.14 MHz requirement, ruling out marginal timing as a suspect.

## No signal
Nothing on a TV or monitor — both fail the same way when no valid clock/sync is
present. That pointed at clock, sync, or power, not color data. Power measured
good (3.29 V). End-to-end continuity, pin by pin, was clean.

## The false positive
Bridge-checking neighboring pins *on a powered board* showed several apparent
shorts. With power removed, none did. Active silicon leaks current through
internal pull-ups and ESD diodes, which a continuity tester reads as a bridge.
Only the unpowered measurement is trustworthy — this was the most useful thing
the whole investigation turned up.

## Isolating the physical layer
25 MHz is invisible to a multimeter, and three failure layers (PLL lock, sync
timing, physical pin path) were bundled into one symptom. Built a minimal
bitstream — no PLL, no external modules — dividing the 12 MHz oscillator down to
a ~0.35 s toggle on every DVI pin. Green/blue held at zero as a control.

**Result:** clock, both syncs, and all four red bits toggled cleanly. `de` did
not.

## Issues with `de`
Several rounds of rework changed the symptom without resolving it. Two
process errors along the way: a measurement taken on `dvi_b[0]` instead of
`dvi_de` (six-position miscount) produced a confident, entirely wrong theory
about a damaged driver; a steady 3.28–3.29 V rail was briefly misread as a
toggle.

The measurement that actually meant something: `de` read ~32.5 Ω to the 3.3 V
rail, symmetric in both probe directions. Compared against `hsync` (known
healthy) reading ~5 MΩ on the same rail — that comparison is what made 32.5 Ω
significant rather than arbitrary.

## Where it ended
32.5 Ω is too high for solder (real bridges read under 1 Ω) but too low to be
nothing. Isopropyl cleaning didn't change it. Two explanations fit every
measurement and are indistinguishable without desoldering the header or a
microscope:
1. A bridge or contamination under the header, off a trace that fans out
   in a way unrelated to connector pin order.
2. A damaged output driver on FPGA pin 32, from an earlier period where it
   was driven against a low-resistance path while powered.

`dvi_de` can't be reassigned — the Pmod's wiring is fixed. **Stopped here.**

## Takeaways
- Continuity checks lie on a powered circuit — only unpowered readings are trustworthy.
- Match the instrument to the problem: an unmeasurable 25 MHz fault became measurable at 0.35 s.
- A control reading (5 MΩ on a known-good pin) is what makes another number mean anything.
- Verify which pin you're actually on before building a theory on it.
