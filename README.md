# UART Transmitter/Receiver with Parity and Error Detection - Verilog

A complete UART (Universal Asynchronous Receiver/Transmitter) implementation in Verilog, supporting configurable parity checking and frame error detection. Built and verified using **Icarus Verilog** and **GTKWave**.

---

## What is UART?

UART is one of the simplest and most widely used serial communication protocols - it's how microcontrollers talk to sensors, GPS modules, Bluetooth chips, and even your laptop's serial console. Unlike SPI or I2C, UART needs no clock signal between devices — both sides just agree on a baud rate beforehand.

A UART frame looks like this:

```
 IDLE   START   D0 D1 D2 D3 D4 D5 D6 D7   PARITY   STOP   IDLE
 ----    |0|     8 data bits (LSB first)    |P|     |1|    ----
 (high) (low)                                       (high)
```

---

## What This Project Does

- **Transmitter (`uart_tx.v`)** — takes an 8-bit byte and serializes it into a UART frame (start bit + 8 data bits + parity bit + stop bit)
- **Receiver (`uart_rx.v`)** — deserializes the incoming UART line back into an 8-bit byte, while checking for two types of errors
- **Configurable parity** — choose NONE, EVEN, or ODD parity via a single parameter
- **Frame error detection** — flags an error if the stop bit isn't actually high (meaning something went wrong with the framing)
- **Parity error detection** — flags an error if the received parity bit doesn't match what was expected

---

## Why I Added Parity and Error Detection

Most beginner UART tutorials only implement the bare minimum (start + data + stop, no error checking). I wanted to go a step further and implement features that real UART peripherals actually have — parity is a basic error-checking mechanism, and frame error detection helps catch corrupted transmissions. Both are pure digital logic (XOR gates and comparators), no extra theory needed beyond standard digital electronics.

---

## File Structure

```
uart_project/
├── uart_tx.v       # Transmitter module
├── uart_rx.v       # Receiver module
├── uart_tb.v        # Testbench: 6 byte tests + 1 frame error injection test
└── README.md
```

---

## How the FSM Works

Both TX and RX use a 5-state finite state machine:

| State | What happens |
|---|---|
| `IDLE` | Line stays high. TX waits for `tx_start`. RX watches for a falling edge (start bit) |
| `START_BIT` | Drive/sample the start bit (always 0) |
| `DATA_BITS` | Send/sample 8 data bits, one per `CLKS_PER_BIT` clock cycles |
| `PARITY_BIT` | Send/sample the parity bit (skipped entirely if parity is disabled) |
| `STOP_BIT` | Send/sample the stop bit (always 1). RX checks here if the stop bit is actually high — if not, that's a frame error |

**Baud rate timing:** `CLKS_PER_BIT = clock_frequency / baud_rate`
Example: 25 MHz clock, 115200 baud → `CLKS_PER_BIT = 217`

---

## How to Run

```bash
iverilog -o uart_sim uart_tb.v uart_tx.v uart_rx.v
vvp uart_sim
gtkwave uart_tb.vcd
```

---

## Test Results

The testbench runs TX and RX in a loopback configuration (TX output feeds directly into RX input) and checks:

| Test | Byte Sent | Result |
|---|---|---|
| 1 | 0x00 | PASS |
| 2 | 0xFF | PASS |
| 3 | 0xAA | PASS |
| 4 | 0x55 | PASS |
| 5 | 0x3F | PASS |
| 6 | 0x7E | PASS |
| 7 (error injection) | 0xA5 (corrupted stop bit) | PASS — frame error correctly detected |

```
=============================
  RESULTS: 7 PASSED, 0 FAILED
=============================
```

---

## What I Learned

- How to design and debug a multi-state FSM in Verilog
- Why mid-bit sampling matters for reliable serial reception (sampling at the centre of a bit period avoids glitches near bit edges)
- How parity works at the hardware level (just an XOR reduction across the data bits)
- How to write a self-checking testbench instead of just eyeballing waveforms

---

## Tools Used

- **Icarus Verilog** — simulation
- **GTKWave** — waveform viewing and debugging
