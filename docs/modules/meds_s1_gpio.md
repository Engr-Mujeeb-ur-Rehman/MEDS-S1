# meds_s1_gpio

## Status
WIP — M-03. The wrapper is wired to the shared register adapter, but
end-to-end AXI verification and M-03 requirement confirmation remain
outstanding.

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
The wrapper passes the core's combinational read data and address-error
response back to the register adapter. GPIO reads have no side effects.

## Register map
See meds_s1_gpio_core.md for offsets, access permissions, reset and
interrupt behavior. Reads have no side effects.

## Verification
Direct GPIO-core tests exist in tb_meds_s1_gpio_core.sv.
They do not demonstrate AXI handshakes or interrupt-controller routing.
Full wrapper tests are still required for AXI handshakes and
interrupt-controller routing.