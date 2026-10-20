# meds_s1_gpio_core

## Status
WIP — M-03. Direct-core tests are provided but have not yet been run.

## Purpose
Implements eight GPIO pins, per-pin direction and output storage,
synchronized input sampling, both-edge detection and sticky per-pin
interrupt status. It contains no AXI handshake implementation.

## Register interface
reg_addr_i is an aligned byte offset. reg_we_i enables a write.
reg_wdata_i contains 32-bit register data and reg_wstrb_i selects bytes.
reg_rdata_o and reg_err_o are combinational.

| Offset | Read | Write |
|---|---|---|
| 0x00 | Direction | Direction bits 7:0 |
| 0x04 | Synchronized inputs | Output bits 7:0 |
| 0x08 | Pending interrupts | Write-one-to-clear bits 7:0 |

Only byte strobe zero affects these eight-bit fields.
Unmapped offsets return zero data and assert reg_err_o.

## Interrupts
Both synchronized edge polarities set pending bits. A new event wins
over simultaneous clearing. Output-pin transitions can also generate
events, preserving the existing implementation. There is no interrupt
enable register, polarity selection or debounce.

## Verification
Testbench: verif/unit/tb_meds_s1_gpio_core.sv.
This tests the register interface and GPIO behavior, not AXI or PLIC.