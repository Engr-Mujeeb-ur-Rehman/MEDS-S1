# `meds_s1_gpio`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | _(assign)_ |
| **Backup** | _(assign)_ |
| **Project** | M-03 |
| **Spec** | SPEC §24, `specs/INTERFACES.md` §3 |
| **Source** | `rtl/peripherals/gpio/meds_s1_gpio.sv` |
| **Testbench** | TODO — `verif/unit/tb_meds_s1_gpio.sv` |

## Purpose

`meds_s1_gpio` provides one memory-mapped GPIO pin with programmable direction and output value. It synchronizes the external pin for software-visible input reads, detects synchronized edges, and latches an interrupt request until software clears it.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | system clock | single clock domain |
| `rst_ni` | in | 1 | active-low reset | asynchronous assertion; registers clear low |
| `s_axi_awaddr_i` | in | `ADDR_WIDTH-2` | write word address | addresses are word-aligned; low byte-offset bits are omitted |
| `s_axi_awvalid_i` | in | 1 | write address/data request | must be asserted with `s_axi_wvalid_i` for acceptance |
| `s_axi_awready_o` | out | 1 | write address ready | pulses when a write request is accepted |
| `s_axi_wdata_i` | in | `DATA_WIDTH` | write data | bit 0 controls GPIO registers; bit 0 also clears the IRQ at offset 0x8 |
| `s_axi_wvalid_i` | in | 1 | write data valid | must be asserted with `s_axi_awvalid_i` |
| `s_axi_wready_o` | out | 1 | write data ready | pulses with `s_axi_awready_o` |
| `s_axi_bresp_o` | out | 2 | write response | always AXI OKAY (`2'b00`) |
| `s_axi_bvalid_o` | out | 1 | write response valid | remains asserted until `s_axi_bready_i` |
| `s_axi_bready_i` | in | 1 | write response ready | completes the write response handshake |
| `s_axi_araddr_i` | in | `ADDR_WIDTH-2` | read word address | addresses are word-aligned; low byte-offset bits are omitted |
| `s_axi_arvalid_i` | in | 1 | read request valid | accepted when the read channel is ready |
| `s_axi_arready_o` | out | 1 | read address ready | pulses when a read address is captured |
| `s_axi_rdata_o` | out | `DATA_WIDTH` | read data | registered response data |
| `s_axi_rresp_o` | out | 2 | read response | always AXI OKAY (`2'b00`) |
| `s_axi_rvalid_o` | out | 1 | read response valid | remains asserted until `s_axi_rready_i` |
| `s_axi_rready_i` | in | 1 | read response ready | completes the read response handshake |
| `gpio_pin_io` | inout | 1 | physical GPIO pin | driven only when the direction register is 1; otherwise high impedance |
| `gpio_irq_o` | out | 1 | GPIO interrupt status | latched high after a synchronized input edge |

**Handshake:** write address and data are accepted together when both valid signals are asserted and the write channel is enabled. Read requests and responses use AXI-Lite-style valid/ready handshakes.

**Latency:** register writes update on the accepting clock edge. A read address is captured first, and the registered read response is produced on the following handshake cycle.

**Backpressure:** one write is held until its response is accepted. A read response remains valid while `s_axi_rready_i` is low.

**Reset state:** control registers, synchronizer stages, interrupt status, AXI ready signals, response valid signals, and read data reset to zero. The pin is high impedance while the direction register is zero.

## Register map

| Offset | Access | Meaning |
|---|---|---|
| `0x0` | RW | GPIO direction in bit 0; 0=input/high impedance, 1=output |
| `0x4` | RW | GPIO output data in bit 0 |
| `0x8` | W1C | Write bit 0 as 1 to clear the latched GPIO interrupt |
| `0x0` | R | Direction register in bit 0 |
| `0x4` | R | Synchronized input value in bit 0 |
| `0x8` | R | Latched interrupt status in bit 0 |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `DATA_WIDTH` | 32 | 32 | AXI register and data width |
| `ADDR_WIDTH` | 4 | 4 | four-byte register window; the module exposes address bits `[ADDR_WIDTH-1:2]` |

## Behaviour

The direction register controls the tri-state output driver. When direction is enabled, `gpio_pin_io` drives the output register; otherwise the pin is released. The input path samples the pin through two synchronizer stages and compares the synchronized value with a one-cycle delayed copy. Any change sets `gpio_irq_o`. A write of 1 to bit 0 at offset `0x8` clears the interrupt latch when no new edge sets it in the same clock cycle.

## Exceptions and errors

- The module returns only AXI OKAY responses; no invalid-address response is implemented.
- Unimplemented register addresses read as zero and do not enable a write register.
- Input changes are observed only after synchronization, so the interrupt is delayed by the synchronizer pipeline.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | TODO | `verif/unit/tb_meds_s1_gpio.sv` not present |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

- There is one GPIO pin and no debounce, filtering, or configurable interrupt polarity.
- The AXI implementation accepts address and data valid together rather than independently buffering the two write channels.

## Open questions

- Assign the module owner and backup before the peripheral interface is frozen.
- Add a focused GPIO unit testbench covering direction, output, synchronized input, edge latch, clear, and AXI backpressure behavior.
