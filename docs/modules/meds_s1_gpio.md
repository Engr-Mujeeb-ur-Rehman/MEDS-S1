# meds_s1_gpio

## Status
WIP — M-03. AXI integration is blocked by the shared register-adapter
skeleton. This wrapper has not been verified end to end.

## Purpose
Connects the official MEDS AXI4-Lite interface to the GPIO register
core. It contains no duplicated AXI channel state machines.

## Interface
The wrapper uses lite_req_t and lite_rsp_t from
rtl/fabric/meds_s1_lite_pkg.sv. Clock and reset are clk_i and rst_ni.
The physical interface is gpio_pin_io[7:0]; gpio_irq_o[7:0] carries
sticky per-pin interrupt status.

## Implementation
meds_s1_lite_regif presents a 32-bit register interface to
meds_s1_gpio_core. ADDR_W defaults to 12 for a 4 KiB window and must
match the actual configured region.

## Register map
See meds_s1_gpio_core.md for offsets, access permissions, reset and
interrupt behavior. Reads have no side effects.

## Verification
Direct GPIO-core tests exist in tb_meds_s1_gpio_core.sv.
They do not demonstrate AXI handshakes or interrupt-controller routing.
Full wrapper tests must be added after the shared adapter is functional.