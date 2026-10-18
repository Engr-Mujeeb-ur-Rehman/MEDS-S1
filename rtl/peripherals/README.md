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

## The bus port — read this before you write a peripheral

Every peripheral here presents **exactly two ports** for the bus, and no others:

```systemverilog
input  lite_req_t lite_req_i,
output lite_rsp_t lite_rsp_o
```

Not one port per AXI signal. The bundle is declared in
[`rtl/fabric/meds_s1_lite_pkg.sv`](../fabric/meds_s1_lite_pkg.sv): the generator (R-04) wires a
peripheral into the crossbar by connecting two named signals, and it cannot do that against a port
list that is different for every peripheral.

Behind those ports, instantiate [`meds_s1_lite_regif`](meds_s1_lite_regif.sv) and implement **only a
register file** — a combinational read decode and a strobed write decode. Nobody writes AXI4-Lite
handshaking twice: the adapter is built once, by T-05, and every peripheral after it just uses it.
Set `REG_DW = 32` unless your registers are genuinely 64-bit wide, as CLINT's are.

## Catalogue projects that land here
M-01 UART · M-02 SPI · M-03 GPIO/timer · T-05 CLINT and PLIC

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
