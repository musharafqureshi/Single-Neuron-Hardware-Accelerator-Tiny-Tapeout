# Tiny Single-Neuron (Perceptron) ReLU Accelerator

A compact hardware implementation of a single artificial neuron with ReLU activation, written in Verilog and taken from RTL to GDSII with a fully open-source flow (Yosys + LibreLane) on the **IHP SG13G2 130 nm** PDK. Designed as a [Tiny Tapeout](https://tinytapeout.com) block and submitted for fabrication.

> Computes `y = ReLU( w0·x0 + w1·x1 + w2·x2 + w3·x3 + b )` using a single shared multiplier.

---

## Overview

The accelerator stores four signed weights, four signed inputs and a bias, all loaded through a simple address / write-enable interface. When `start` is asserted, an 8-state FSM time-multiplexes **one 6×6 signed multiplier** across the four products and accumulates them, together with the bias, in a 16-bit accumulator. A ReLU stage then clamps negative sums to zero and saturates large positive sums at 255, producing an 8-bit result. `busy` and `done` flags provide handshaking.

Reusing one multiplier instead of instantiating four keeps the area small, which suits the tight tile budget of Tiny Tapeout.

### Key features

| Feature | Detail |
|---|---|
| Weights | 4 × 6-bit signed |
| Inputs | 4 × 6-bit signed |
| Bias | 1 × 6-bit signed |
| Multiplier | 1 × shared 6×6 signed (time-multiplexed) |
| Accumulator | 16-bit |
| Activation | ReLU: negative → 0, positive saturates at 255 |
| Output | 8-bit unsigned |
| Control | 8-state FSM, `start` / `busy` / `done` handshake |
| Latency | ~6 clock cycles per inference |
| Register file | Loaded via address + write-enable interface |

### Intended uses

- Building block for edge-AI classifiers
- Neural-network hardware demos and teaching
- Starting point for larger multi-neuron layers

---

## Architecture

```
          +-----------------------------------------------+
 addr  -->|  Register file                                |
 data  -->|  w0..w3 (6b)  x0..x3 (6b)  bias (6b)          |
 we    -->|                                               |
          +-------------------+---------------------------+
                              |
 start -->   +----------------v---------------+
             |   8-state FSM (control)        |--> busy
             +----------------+---------------+--> done
                              | select i
                     +--------v--------+
                     | 6x6 signed MUL  |   (shared)
                     +--------+--------+
                              |
                     +--------v--------+
                     | 16-bit ACC + b  |
                     +--------+--------+
                              |
                     +--------v--------+
                     | ReLU + sat @255 |--> result[7:0]
                     +-----------------+
```

---

## Interface

27 pins in total: 8 inputs, 8 outputs, 8 bidirectional, plus `clk`, `rst_n` and `ena`.

| Signal | Direction | Description |
|---|---|---|
| `clk` | in | Clock (target 64 MHz) |
| `rst_n` | in | Active-low reset |
| `ena` | in | Tiny Tapeout enable |
| `ui_in[7:0]` | in | _TODO: describe (e.g. data / address / start)_ |
| `uo_out[7:0]` | out | _TODO: describe (e.g. 8-bit ReLU result)_ |
| `uio[7:0]` | bidir | _TODO: describe (e.g. address, write-enable, busy, done)_ |

> Fill in the exact pin mapping from your `info.yaml` / top-level module.

### Usage sequence

1. Reset the design (`rst_n` low, then high).
2. Write the weights, inputs and bias through the address / write-enable interface.
3. Assert `start`.
4. Wait for `busy` to clear and `done` to assert (~6 cycles).
5. Read the 8-bit result.

---

## Implementation results

| Item | Value |
|---|---|
| Language | Verilog |
| Synthesis | Yosys |
| RTL-to-GDS flow | LibreLane |
| PDK | IHP SG13G2 (130 nm) |
| Target clock | 64 MHz (15.625 ns period) |
| Cell area (synthesis) | ~9,818 µm² |
| Cell count | 634 |
| Flip-flops | 81 |

---

## Repository structure

> Adjust to match your repo.

```
.
├── src/            # Verilog RTL
├── test/           # Testbench (cocotb / Verilog)
├── docs/           # Documentation, diagrams
├── info.yaml       # Tiny Tapeout metadata
└── README.md
```

## Simulation

```bash
# Example (adjust to your testbench setup)
cd test
make
```

## Build with LibreLane

```bash
# Example (adjust to your setup)
librelane config.yaml
```

---

## Status

Submitted to Tiny Tapeout.

## Author

**Mohammed Musharaf Qureshi**
ECE, Muffakham Jah College of Engineering and Technology, Hyderabad

## Acknowledgements

- [Tiny Tapeout](https://tinytapeout.com)
- [LibreLane](https://github.com/librelane/librelane)
- [Yosys](https://github.com/YosysHQ/yosys)
- [IHP Open PDK (SG13G2)](https://github.com/IHP-GmbH/IHP-Open-PDK)
