// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_lite_regif : AXI4-Lite slave -> register-file adapter [SKELETON -- T-05]
//
// The AXI4-Lite slave handshake, written ONCE.  Every MEDS-S1 peripheral
// instantiates this and then implements only a register file.  CLINT, PLIC,
// UART, SPI, GPIO and every accelerator MMIO window sit behind it, so this is
// the single most reused module either of you will write this semester.  Build
// it first, and build it carefully.
//
// The PORT LIST below is frozen -- it is the contract four other projects will
// code against.  The BODY is yours.
//
// Contract, stated once so your testbench has something to check against:
//
//   we_o / re_o   one-cycle strobes, never both in the same cycle
//   addr_o        BYTE offset inside the window, aligned down to REG_DW/8, so a
//                 peripheral's decode is a case on the offsets in its own
//                 register-map table -- no shifting, no slot arithmetic
//   wdata_o       write data, already shifted out of its bus lane
//   wstrb_o       byte enables for that register
//   rdata_i       COMBINATIONAL read data, valid in the same cycle as re_o
//   err_i         combinational from addr_o: "nothing is mapped here"
//
// Reference: INTERFACES.md section 3 (I4), ADR-0005.
// Full contract: docs/modules/meds_s1_lite_regif.md -- read it before you start,
// it is the specification you are implementing.
// Testbench: verif/unit/tb_meds_s1_lite_regif.sv
// =============================================================================

module meds_s1_lite_regif
  import meds_s1_lite_pkg::*;
#(
  // Window size in address bits: 64 KiB -> 16, 4 MiB -> 22.  Comes from the
  // region's `size` in configs/*.yaml; never hand-written in two places.
  parameter int unsigned ADDR_W = 16,
  // Register-file width.  Must be LITE_DW (64) or LITE_DW/2 (32).
  parameter int unsigned REG_DW = 32
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  // ---- I4 bus port.  FROZEN.  Do not add signals here. ----------------------
  input  lite_req_t           lite_req_i,
  output lite_rsp_t           lite_rsp_o,

  // ---- register-file port.  FROZEN.  This is the side a peripheral sees. ----
  output logic [ADDR_W-1:0]   addr_o,
  output logic                we_o,
  output logic                re_o,
  output logic [REG_DW-1:0]   wdata_o,
  output logic [REG_DW/8-1:0] wstrb_o,
  input  logic [REG_DW-1:0]   rdata_i,
  input  logic                err_i
);

  // ===========================================================================
  // TODO(T-05) -- everything below this line.  Delete the scaffolding at the
  // bottom as each step lands.  Suggested order, because each step is testable
  // on its own:
  //
  //  1. CHANNEL CAPTURE.  Give AW, W, AR, B and R one holding register each,
  //     with a `full` flag.  Drive each `ready` from its own `full` flag.
  //
  //     Capture AW and W INDEPENDENTLY and in EITHER ORDER.  AXI4-Lite permits
  //     a master to present W before AW, and a slave that waits for AW first
  //     deadlocks against such a master.  This is the single most common bug in
  //     a hand-written AXI-Lite slave and it never shows up in a happy-path
  //     test, because a simple driver always sends AW first.
  //
  //  2. R-C10.  No `ready` may depend on its own `valid`, and no `valid` may
  //     depend on a `ready`.  Get this wrong and you can still pass every test
  //     you are likely to write, then deadlock against the real crossbar.  Ask
  //     yourself what `lite_rsp_o.b_valid` is a function of, and write the
  //     answer in the module page.
  //
  //  3. EXECUTE.  A write executes when AW and W are both held and the B
  //     channel is free; a read when AR is held and R is free.  The register
  //     file serves ONE access per cycle, so when both are queued you must
  //     choose.  Choose in a way that cannot starve either forever, and say in
  //     the module page why your choice cannot.
  //
  //  4. ADDRESS.  addr_o is a byte offset with the sub-register bits forced to
  //     zero.  Store only the window bits: everything above ADDR_W was already
  //     decoded by the crossbar, and the bits below REG_DW/8 carry no
  //     information on AXI4-Lite -- sub-register addressing is expressed by the
  //     strobes, not the address.
  //
  //  5. BYTE LANE.  This is the whole reason the module is parameterised.  With
  //     REG_DW = 32 on the 64-bit bus, one address bit says which half of the
  //     bus word the register occupies.  Work out which bit.  Shift write data
  //     and strobes DOWN into the register's width; shift read data UP into the
  //     addressed lane.  With REG_DW = 64 there is no lane to pick.
  //
  //     Write it so both parameter values elaborate without a width warning --
  //     `-Wall` is part of the merge gate, and a part-select whose range
  //     reverses when a parameter changes is a compile error, not a warning.
  //
  //  6. ERRORS.  err_i means SLVERR.  There is one more error case: with
  //     REG_DW = 32, a write whose strobes span BOTH lanes is an 8-byte access
  //     to a peripheral that has no 8-byte registers.  Report it rather than
  //     silently dropping half of it (INTERFACES.md rule P3), and do not write
  //     the register file at all when you do.
  //
  //     Reads cannot be caught the same way.  Work out why, and record it as a
  //     known limitation on the module page -- an unstated limitation is a bug,
  //     a stated one is a decision.
  //
  //  7. ELABORATION CHECK.  REG_DW must be LITE_DW or LITE_DW/2.  Fail loudly
  //     at elaboration rather than mis-decoding at run time.
  // ===========================================================================

  // ---- SCAFFOLDING -- delete as the steps above land ------------------------
  // Drives safe values so the skeleton elaborates and `make lint` stays green.
  // None of this is a hint about the implementation.
  assign lite_rsp_o = LITE_RSP_IDLE;
  assign addr_o     = '0;
  assign we_o       = 1'b0;
  assign re_o       = 1'b0;
  assign wdata_o    = '0;
  assign wstrb_o    = '0;

  logic unused_ok;
  assign unused_ok = clk_i | rst_ni | err_i | (|rdata_i) | (|lite_req_i);

endmodule
