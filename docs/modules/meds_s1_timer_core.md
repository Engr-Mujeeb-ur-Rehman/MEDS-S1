# meds_s1_timer_core

## Status
WIP — M-03. Register-level implementation follows the instructor clarification:
expiry clears the count in both modes. All 51 checks passed in the updated
local timer testbench; structure checks and lint passed. These changes have
not yet run in remote CI. AXI and system integration remain pending.

## Purpose
Implements the timer register file, 32-bit counter, equality comparator,
periodic/one-shot selection and sticky interrupt status. No AXI logic is present.

## Register interface
`reg_addr_i` is an aligned byte offset. Writes use `reg_we_i`,
`reg_wdata_i[31:0]` and `reg_wstrb_i[3:0]`. Read data (`reg_rdata_o`)
and address errors (`reg_err_o`) are combinational. Reads have no side effects.

| Offset | Register | Read | Write |
|---|---|---|---|
| 0x00 | CTRL | EN bit 0, ONESHOT bit 1, IRQ_PENDING bit 2 | EN/MODE replacement; bit 2 write-one-to-clear |
| 0x04 | COMPARE | compare_q[31:0] | Independently byte-strobed update |
| 0x08 | COUNT | count_q[31:0] | Ignored |

CTRL changes require byte strobe 0; other CTRL bits are reserved and read zero.
Unmapped offsets return zero data, assert `reg_err_o`, and do not change registers.
All stored state resets to zero under `rst_ni`. All sequential logic uses `clk_i`.

## Counting and mode selection
`timer_match = (count_q == compare_q)` and `timer_event = enabled_q && timer_match`.
A disabled timer holds its count. An enabled timer increments when no event occurs.
Every event clears the count synchronously to zero and sets interrupt pending.

| MODE bit 1 | Mode | Count at expiry | Enable after expiry |
|---|---|---|---|
| 0 | Periodic | 0 | Remains 1 |
| 1 | One-shot | 0 | Clears to 0 |

The comparator examines the pre-edge count. Starting from zero, a maximum N
produces an event after N+1 enabled edges. With COMPARE=3 the sequence after
counting edges is 1, 2, 3, 0 (event). With COMPARE=0 the first enabled edge
expires; periodic mode then generates an event every enabled edge.
An enable write from disabled state takes effect for counting on the next edge.
Rearming an expired one-shot starts from zero; disabling mid-interval holds the
partial count and re-enabling resumes it. No new software count-clear register
is introduced. The counter wraps modulo 2^32.

## Priorities and software usage
A new event wins over interrupt clearing. One-shot expiry wins over a simultaneous
CTRL enable/mode write, so the timer remains stopped and keeps its one-shot mode.
Software compare writes and event decisions on one edge use normal synchronous
semantics: the event is evaluated using the old count, enable, mode and compare.

CTRL bit 2 is W1C, but bits 0 and 1 are written in the same access. Preserve the
desired EN/MODE values when clearing pending: 0x5 clears pending while running
periodically; 0x6 clears pending while keeping an expired one-shot stopped;
0x7 clears pending and rearms one-shot operation.

Program COMPARE and MODE while disabled. Equality differs from the previous >=
comparison: setting COMPARE below the running count does not trigger immediately;
a match can be delayed until counter wraparound. Avoid changing the threshold
mid-interval unless that behavior is intended.

## Scope and verification
This is an enabled, restart-on-expiry timer per the instructor clarification,
not a continuously free-running timebase. Counter clear is synchronous data
control; no comparator-driven reset or combinationally gated clock is used.
The output `timer_irq_o` is sticky status, not a one-cycle event pulse.

Testbench: `verif/unit/tb_meds_s1_timer_core.sv`. Tests cover register reset,
byte strobes, unmapped access, read-only COUNT, periodic repetition, count clear
in both modes, one-shot rearming, zero compare, disable/hold, equality behavior,
and simultaneous expiry/CTRL/W1C priority. All 51 checks passed locally; previous 29-check CI results apply
to the old behavior. AXI/PLIC/processor integration is not covered here.
