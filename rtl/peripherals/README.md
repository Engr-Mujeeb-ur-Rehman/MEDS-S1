# `rtl/peripherals/` — Peripherals

## What lives here
CLINT, PLIC, UART, SPI, GPIO, timers — mostly thin wrappers around reused IP.

## What does *not* live here
Anything invented here without a reuse justification (SCOPE_CONTRACT.md §5).

## How to add something
Wrap the IP behind the shared Lite request/response structures, connect the
AXI4-Lite adapter at the fabric boundary, add it to a config YAML, write the
unit testbench and the HAL driver in `sw/bsp/`. Record the upstream source and
licence in the module README.

## Catalogue projects that land here
M-01 UART · M-02 SPI · M-03 GPIO/timer · T-05 CLINT and PLIC

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
