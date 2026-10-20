# meds_s1_timer

## Status
WIP — M-03. AXI integration is blocked by the shared register-adapter
skeleton. This wrapper has not been verified end to end.

## Purpose
Connects the official MEDS AXI4-Lite interface to the timer register
core without implementing independent bus handshake logic.

## Interface
The wrapper uses lite_req_t and lite_rsp_t from
rtl/fabric/meds_s1_lite_pkg.sv. Clock and reset are clk_i and rst_ni.
timer_irq_o is the timer's sticky interrupt output.

## Implementation
meds_s1_lite_regif presents a 32-bit register interface to
meds_s1_timer_core. ADDR_W defaults to 12 for a 4 KiB region and must
match the actual system configuration.

## Register map and semantics
See meds_s1_timer_core.md. This version preserves the original
enabled-counter behavior; it does not claim compliance with a
continuously free-running-counter requirement.

## Verification
Direct timer-core tests exist in tb_meds_s1_timer_core.sv.
Full AXI, PLIC and processor-driven LED verification remains pending.
Passing core tests must not be reported as completed M-03 integration.