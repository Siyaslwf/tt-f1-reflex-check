# 🏁 F1 Reflex Precision Trainer: Silicon Reaction Console
*A Hardware-Accelerated Millisecond Reaction Timer Compiled Into Physical Silicon*

[![gds](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/gds.yaml/badge.svg)](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/gds.yaml)
[![docs](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/docs.yaml/badge.svg)](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/docs.yaml)
[![test](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/test.yaml/badge.svg)](https://github.com/Siyaslwf/tt-f1-reflex-check/actions/workflows/test.yaml)

---

## ⚡ Overview
Inspired by Formula 1 driver reaction training, this project is a custom digital hardware device synthesized directly onto a SkyWater 130nm ASIC tile. 

It features an asynchronous-to-synchronous dual-flop synchronizer, a hardware 1,000 Hz millisecond clock divider, a pseudo-random LFSR blackout timer, an algorithmic 7-segment digital font engine, and a 60Hz 640x480 VGA telemetry display controller.

---

## 🎮 How It Works (Gameplay)
1. **The Gantry Sequence:** Press **Button 0 (`ui_in[0]`)** to initiate the sequence. Five columns of dual red start lamps light up sequentially from left to right.
2. **The Blackout:** After all lamps illuminate, a randomized hardware delay fires, and **all lights instantly turn off**.
3. **The Reflex Capture:** The moment the lights drop, a millisecond-precision stopwatch counts up from `00.00` on the screen. Pressing Button 0 again halts the timer. 
4. **Pro Evaluation:** If your reaction time beats professional F1 thresholds (< 250ms), the screen flashes a brilliant **Victory Green**.

---

## 🛠️ Tech Stack & Toolchain
* **Hardware Language:** Verilog (IEEE 1364-2005)
* **Target Architecture:** SkyWater 130nm ($1\times1$ Tiny Tapeout Tile)
* **Synthesis & P&R:** LibreLane / OpenROAD
* **Verification:** Cocotb & Icarus Verilog
