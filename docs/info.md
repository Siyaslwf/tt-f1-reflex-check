# F1 Reflex Precision Trainer

## How it works
This chip implements an F1 starting lights reaction time tester on a 640x480 60Hz VGA display using synchronous Verilog hardware logic. It features a sequential 5-column starting light gantry, an LFSR randomizer, and a millisecond-precision stopwatch counter.

## How to test
1. Connect a TinyVGA Pmod to the output port.
2. Press `ui_in[0]` (Start) to
