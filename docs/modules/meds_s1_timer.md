# `meds_s1_timer`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | _(assign)_ |
| **Backup** | _(assign)_ |
| **Project** | M-03 |
| **Spec** | SPEC §24, `specs/INTERFACES.md` §3 |
| **Source** | `rtl/peripherals/timer/meds_s1_timer.sv` |
| **Testbench** | passing — `verif/unit/tb_meds_s1_timer.sv` |

## Purpose

`meds_s1_timer` provides a memory-mapped timer with enable and mode control, a
programmable compare value, a readable counter, and a latched IRQ. It supports
periodic and one-shot operation for simple software timing and timeout
services.

## Interface contract

The peripheral exposes the shared 32-bit Lite structures from
`rtl/common/meds_s1_lite_pkg.sv`:

```systemverilog
module meds_s1_timer
	import meds_s1_lite_pkg::*;
(
		input  logic      clk_i,
		input  logic      rst_ni,
		input  lite_req_t lite_req_i,
		output lite_rsp_t lite_rsp_o,
		output logic      timer_irq_o
);
```

`lite_req_i.addr` is a byte address. Requests use `valid`, `write`, `wdata`,
and `wstrb`; the peripheral accepts them when `lite_rsp_o.ready` is high.
Reads return combinational register data in `lite_rsp_o.rdata` with
`lite_rsp_o.valid`. AXI-Lite channel handshakes and AXI responses are owned by
`meds_s1_lite_axi_adapter`; timer contains no AXI FSM or AXI ports.

| Signal | Direction | Width | Meaning |
|---|---|---:|---|
| `clk_i` | in | 1 | system clock |
| `rst_ni` | in | 1 | asynchronous active-low reset |
| `lite_req_i` | in | shared | full byte address, request, data, and strobes |
| `lite_rsp_o` | out | shared | ready/valid response and read data |
| `timer_irq_o` | out | 1 | latched interrupt status |

**Handshake:** the shared adapter accepts AXI address and data together, then
provides one Lite request. Timer is always ready and returns a valid response.

**Latency:** writes update on the accepting clock edge; reads return
combinational register data for the active Lite request.

**Backpressure:** the peripheral is always ready. The shared adapter holds an
AXI response until the external AXI master accepts it.

**Terminology:** AXI means Advanced eXtensible Interface; IRQ means interrupt
request; W1C means write-one-to-clear; backpressure means the receiver can
temporarily deassert ready while the producer holds valid data stable.

**Reset state:** enable, mode, compare, counter, interrupt status, and read
data reset to zero.

## Register map

| Offset | Read behavior | Write behavior |
|---|---|---|
| `0x00` | Returns enable, mode, and IRQ status | Updates enable/mode; bit 2 is W1C for IRQ |
| `0x04` | Returns compare value | Updates compare value |
| `0x08` | Returns current counter | Reserved for writes |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| Shared package | 32-bit | fixed | Lite request/response, compare, and counter width |
| Address width | 4 bits | fixed | byte offsets `0x0`, `0x4`, and `0x8` |

## Behaviour

When enabled, the counter increments once per clock. The action condition is
true when the counter is greater than or equal to compare and the timer is
enabled. The action latches `timer_irq_o`. Periodic mode resets the counter;
one-shot mode disables the timer after the action. A simultaneous action and
clear leaves IRQ asserted because action has priority.

## Exceptions and errors

- Unimplemented register addresses read as zero and do not enable a write register.
- A compare value of zero causes an enabled timer to take the action condition immediately.
- The interrupt is level-latched in the register until software clears it; a new action has priority over a simultaneous clear.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | passing, 33 checks | `verif/unit/tb_meds_s1_timer.sv` |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

- There is no prescaler, watchdog mode, separate interrupt enable, or periodic reload register.
- The compare condition is `counter >= compare`, not equality-only matching.
- The shared adapter accepts address and data together; timer does not buffer AXI channels.

## Open questions

- Assign the module owner and backup before the peripheral interface is frozen.
