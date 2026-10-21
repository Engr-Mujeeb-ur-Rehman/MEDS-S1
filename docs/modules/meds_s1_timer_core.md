# meds_s1_timer_core

## Status
WIP — M-03. Direct-core verification passed 29 checks in CI at
commit 5205058. AXI integration and M-03 requirement confirmation
remain outstanding.

## Purpose
Separates the existing timer register and datapath behavior from AXI.
This refactor preserves existing counting semantics while fixing
byte-strobed compare writes.

## Register interface
Addresses are aligned byte offsets. Writes use reg_we_i, reg_wdata_i
and reg_wstrb_i. Read data and address errors are combinational.

| Offset | Read | Write |
|---|---|---|
| 0x00 | Enable, mode, IRQ | Enable, mode, W1C IRQ |
| 0x04 | Compare | Byte-strobed compare update |
| 0x08 | Count | Ignored |

Control bit 0 enables counting; bit 1 selects one-shot when set.
Bit 2 reads interrupt status and clears it when written as one.
Unmapped offsets assert reg_err_o and return zero data.

## Behavior and priorities
Match means count greater than or equal to compare while enabled.
Periodic events reset the count. One-shot events disable the timer.
A new interrupt wins over clearing. One-shot halt has priority over
a simultaneous control update.

## Known limitations
The counter is not continuously free-running. Periodic timing is
compare plus one counting clocks. The one-shot match edge increments
the count once before stopping, and re-enabling retains that count.
These existing semantics need review against M-03 before completion.

## Verification
Testbench: verif/unit/tb_meds_s1_timer_core.sv.

All 29 checks passed in CI at commit 5205058. Tests cover reset,
register access, byte strobes, invalid addresses, periodic operation,
one-shot operation, and interrupt clearing/event priority.

Verification covers the core register interface and timer behavior.
It does not verify AXI, PLIC or software integration.