# `meds_s1_timer`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | _(assign)_ |
| **Backup** | _(assign)_ |
| **Project** | M-03 |
| **Spec** | SPEC §24, `specs/INTERFACES.md` §3 |
| **Source** | `rtl/peripherals/timer/meds_s1_timer.sv` |
| **Testbench** | TODO — `verif/unit/tb_meds_s1_timer.sv` |

## Purpose

`meds_s1_timer` provides a memory-mapped timer with enable and mode control, a programmable compare value, a readable counter, and a latched interrupt output. It supports periodic operation and one-shot operation for simple software timing and timeout services.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | system clock | single clock domain |
| `rst_ni` | in | 1 | active-low reset | asynchronous assertion; registers clear low |
| `s_axi_awaddr_i` | in | `ADDR_WIDTH-2` | write word address | addresses are word-aligned; low byte-offset bits are omitted |
| `s_axi_awvalid_i` | in | 1 | write address request | must be asserted with `s_axi_wvalid_i` for acceptance |
| `s_axi_awready_o` | out | 1 | write address ready | pulses when a write request is accepted |
| `s_axi_wdata_i` | in | `DATA_WIDTH` | write data | control uses bits 0-2; compare writes use the full value |
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
| `timer_irq_o` | out | 1 | timer interrupt status | latched high when the enabled counter reaches or exceeds compare |

**Handshake:** write address and data are accepted together when both valid signals are asserted and the write channel is enabled. Read requests and responses use AXI-Lite-style valid/ready handshakes.

**Latency:** register writes update on the accepting clock edge. A read address is captured first, and the registered read response is produced on the following handshake cycle.

**Backpressure:** one write is held until its response is accepted. A read response remains valid while `s_axi_rready_i` is low.

**Reset state:** enable, mode, compare, counter, interrupt status, AXI ready signals, response valid signals, and read data reset to zero.

## Register map

| Offset | Access | Meaning |
|---|---|---|
| `0x0` | RW | Control: bit 0 enable, bit 1 mode (0=periodic, 1=one-shot), bit 2 software interrupt clear |
| `0x4` | RW | Compare value; full `DATA_WIDTH` is stored |
| `0x8` | R | Current counter value |
| `0x0` | R | Control status: bit 0 enable, bit 1 mode, bit 2 interrupt status |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `DATA_WIDTH` | 32 | 32 | AXI register, compare, and counter width |
| `ADDR_WIDTH` | 4 | 4 | four-byte register window; the module exposes address bits `[ADDR_WIDTH-1:2]` |

## Behaviour

When enabled, the counter increments once per clock. The timer action condition is true when the counter is greater than or equal to the compare register and the timer is enabled. The action latches `timer_irq_o`. In periodic mode it also forces the counter to zero; in one-shot mode it disables the timer after the action. Software clears the interrupt by writing bit 2 at offset `0x0`. Reads return the control status, compare value, or current counter for the corresponding register offset; other offsets read as zero.

## Exceptions and errors

- The module returns only AXI OKAY responses; no invalid-address response is implemented.
- Unimplemented register addresses read as zero and do not enable a write register.
- A compare value of zero causes an enabled timer to take the action condition immediately.
- The interrupt is level-latched in the register until software clears it; a new action has priority over a simultaneous clear.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | TODO | `verif/unit/tb_meds_s1_timer.sv` not present |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

- There is no prescaler, watchdog mode, separate interrupt enable, or periodic reload register.
- The compare condition is `counter >= compare`, not equality-only matching.
- The AXI implementation accepts address and data valid together rather than independently buffering the two write channels.

## Open questions

- Assign the module owner and backup before the peripheral interface is frozen.
- Add a focused timer unit testbench covering periodic and one-shot operation, compare-zero behavior, IRQ clear, reads, and AXI backpressure.
