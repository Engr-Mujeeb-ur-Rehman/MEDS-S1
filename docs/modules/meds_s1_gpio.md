# `meds_s1_gpio`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | _(assign)_ |
| **Backup** | _(assign)_ |
| **Project** | M-03 |
| **Spec** | SPEC §24, `specs/INTERFACES.md` §3 |
| **Source** | `rtl/peripherals/gpio/meds_s1_gpio.sv` |
| **Testbench** | passing — `verif/unit/tb_meds_s1_gpio.sv` |

## Purpose

`meds_s1_gpio` provides an eight-bit memory-mapped GPIO bank with independent
direction and output values. Each pin is synchronized for software-visible
input reads, both synchronized edge polarities are detected per bit, and IRQ
status remains latched until selected bits are cleared.

## Interface contract

The peripheral exposes the shared 32-bit Lite structures from
`rtl/common/meds_s1_lite_pkg.sv`:

```systemverilog
module meds_s1_gpio
	import meds_s1_lite_pkg::*;
(
		input  logic      clk_i,
		input  logic      rst_ni,
		input  lite_req_t lite_req_i,
		output lite_rsp_t lite_rsp_o,
		inout  logic [7:0] gpio_pin_io,
		output logic [7:0] gpio_irq_o
);
```

`lite_req_i.addr` is a byte address. Requests use `valid`, `write`, `wdata`,
and `wstrb`; the peripheral accepts them when `lite_rsp_o.ready` is high.
Reads return combinational register data in `lite_rsp_o.rdata` with
`lite_rsp_o.valid`. AXI-Lite channel handshakes and AXI responses are owned by
`meds_s1_lite_axi_adapter`; GPIO contains no AXI FSM or AXI ports.

| Signal | Direction | Width | Meaning |
|---|---|---:|---|
| `clk_i` | in | 1 | system clock |
| `rst_ni` | in | 1 | asynchronous active-low reset |
| `lite_req_i` | in | shared | full byte address, request, data, and strobes |
| `lite_rsp_o` | out | shared | ready/valid response and read data |
| `gpio_pin_io` | inout | 8 | independent physical GPIO pins; high impedance per direction bit |
| `gpio_irq_o` | out | 8 | latched per-pin interrupt status |

**Handshake:** the shared adapter accepts AXI address and data together, then
provides one Lite request. GPIO is always ready and returns a valid response.

**Latency:** writes update on the accepting clock edge; reads return
combinational register data for the active Lite request.

**Backpressure:** the peripheral is always ready. The shared adapter holds an
AXI response until the external AXI master accepts it.

**Terminology:** AXI means Advanced eXtensible Interface; IRQ means interrupt
request; W1C means write-one-to-clear; backpressure means the receiver can
temporarily deassert ready while the producer holds valid data stable.

**Reset state:** control registers, synchronizer stages, interrupt status, and
read data reset to zero. The pin is high impedance while direction is zero.

## Register map

| Offset | Read behavior | Write behavior |
|---|---|---|
| `0x00` | Returns direction bits `[7:0]` | Updates direction bits `[7:0]` |
| `0x04` | Returns synchronized input bits `[7:0]` | Updates output bits `[7:0]` |
| `0x08` | Returns latched IRQ bits `[7:0]` | W1C: writing 1 to selected bits clears those IRQs |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| Shared package | 32-bit | fixed | Lite request/response data width; GPIO uses the low byte |
| Address width | 4 bits | fixed | byte offsets `0x00`, `0x04`, and `0x08` |

## Behaviour

Each direction bit controls one tri-state output driver. The input path uses
`syn1_q` as the first synchronization stage, `syn2_q` as the second stage, and
`delay_q` as the previous synchronized sample. XOR detects both rising and
falling edges independently for each pin; this is not debounce logic. A W1C
write clears selected latched IRQ bits, but a new edge has priority for that
bit during a simultaneous clear.

## Exceptions and errors

- Unimplemented register addresses read as zero and do not enable a write register.
- Input changes are observed only after synchronization, so the interrupt is delayed by the synchronizer pipeline.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | passing, 27 checks | `verif/unit/tb_meds_s1_gpio.sv` |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

- There is no debounce, filtering, or configurable interrupt polarity.
- The shared adapter accepts address and data together; GPIO does not buffer AXI channels.

## Open questions

- Assign the module owner and backup before the peripheral interface is frozen.
