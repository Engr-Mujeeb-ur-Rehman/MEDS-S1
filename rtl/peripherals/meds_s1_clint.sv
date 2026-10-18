// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_clint : core-local interruptor                      [SKELETON -- T-05]
//
// Software (msip) and timer (mtime / mtimecmp) interrupts.
//
// MEDS-S1 is a SINGLE-HART platform, so there is no hart index anywhere in this
// module: one msip bit, one mtimecmp, one mtime, one of each interrupt line.
// A future multi-hart port changes this file and the register map together;
// that is a deliberate decision, not an oversight (ADR-0005).
//
// The PORT LIST below is frozen.  The BODY is yours.
//
// Reference: SPEC section 24, INTERFACES.md section 6 (I7), ADR-0005.
// Register map: docs/modules/meds_s1_clint.md -- fill in the reset and width
// columns from the specification BEFORE you write any logic here.
// Testbench: verif/unit/tb_meds_s1_clint.sv  <- you write this.
//
// -----------------------------------------------------------------------------
// PORTING AN EXISTING CLINT INTO THIS SHELL
//
// If your module currently looks like this, one port per bus wire:
//
//     module clint (
//       input  logic        clk_i, rst_ni,
//       input  logic [31:0] awaddr_i,  input  logic awvalid_i, output logic awready_o,
//       input  logic [31:0] wdata_i,   input  logic [3:0] wstrb_i,
//       output logic [1:0]  bresp_o,   output logic bvalid_o,  input  logic bready_i,
//       ... eleven more ...
//     );
//
// ...then your LOGIC is fine and your PORT LIST is not.  Three mechanical steps:
//
//   1. Delete every AXI port and every line of your own handshake FSM.  Replace
//      them with the two struct ports below.  meds_s1_lite_regif is that FSM,
//      written once for every peripheral on the bus.
//
//   2. Your read decode becomes a combinational block keyed on `addr_o`.  Your
//      write decode becomes a clocked block keyed on `we_o`, `addr_o` and
//      `wstrb_o`.  Your register declarations and update logic cross over
//      unchanged.
//
//   3. Anything you split into two 32-bit halves because the bus was narrow --
//      mtime, mtimecmp -- collapses back into one 64-bit register.  The bus is
//      64 bits wide and REG_DW is 64, so one access carries the whole thing.
//
// Why the struct and not twenty ports: the generator (R-04) wires every
// peripheral into the crossbar by connecting two named signals.  It cannot wire
// a port list that is different for every peripheral, and a bus that gains a
// signal would otherwise mean editing every peripheral in the tree.
// =============================================================================

module meds_s1_clint
  import meds_s1_lite_pkg::*;
(
  input  logic       clk_i,
  input  logic       rst_ni,

  // Free-running real-time tick, one clk_i cycle wide, generated in board_top
  // at rtc_hz (SPEC section 25).  mtime counts THIS, never clk_i -- otherwise
  // every delay loop in the BSP changes meaning when the FPGA frequency does.
  input  logic       rtc_tick_i,

  // ---- the frozen I4 bus port.  Do not add signals here. --------------------
  input  lite_req_t  lite_req_i,
  output lite_rsp_t  lite_rsp_o,

  // ---- interrupt lines to the core's mip CSR --------------------------------
  output logic       msip_o,
  output logic       mtip_o
);

  // Window geometry.  64 KiB, from the `clint` region in configs/*.yaml.
  // REG_DW is 64 because mtime and mtimecmp must be readable in ONE access.
  localparam int unsigned ADDR_W = 16;
  localparam int unsigned REG_DW = 64;

  // ===========================================================================
  // TODO(T-05) -- everything below.  Delete the scaffolding as each step lands.
  //
  //  1. BUS ADAPTER.  Declare the register-file wires (addr, we, re, wdata,
  //     wstrb, rdata, err -- widths from ADDR_W and REG_DW above) and
  //     instantiate meds_s1_lite_regif with .ADDR_W(ADDR_W) and .REG_DW(REG_DW).
  //     This is the only structural thing in the file; everything after it is a
  //     register file.
  //
  //  2. REGISTER STORAGE.  Three registers: msip (1 meaningful bit), mtimecmp
  //     (64), mtime (64).  Reset values come from your register-map table, and
  //     the mtimecmp reset value is a real decision -- if it resets to zero then
  //     mtime >= mtimecmp is true immediately and mtip asserts out of reset.
  //     Decide, then make the table and the RTL agree.
  //
  //  3. READ DECODE.  Combinational, valid in the same cycle as `re`.  `err`
  //     means "nothing is mapped at this offset" and becomes SLVERR, so default
  //     it to 1 and have each mapped offset clear it.  Take the three offsets
  //     from the register map; declare them as localparams, not as literals
  //     buried in the logic (R-C7).
  //
  //  4. WRITE DECODE.  Clocked, on `we`.  HONOUR `wstrb`: it says which bytes
  //     of the access the master actually wrote.  Ignoring it means a 4-byte
  //     write to one half of a 64-bit register silently clears the other half,
  //     which is exactly the bug that the low/high mtimecmp update sequence
  //     exists to avoid.
  //
  //     mtime is architecturally writable too -- that is how software sets the
  //     clock -- and a write to mtimecmp must retire a pending timer interrupt
  //     in the SAME access, or a handler cannot clear its own interrupt.
  //
  //  5. mtime.  Advances on rtc_tick_i and on nothing else.  It must keep
  //     counting while the bus is reading it.
  //
  //  6. mtip.  LEVEL, and exactly one comparison.  Think hard about whether it
  //     is `==` or `>=`, and write the reason in the module page: one of the two
  //     misses the interrupt forever whenever the comparand is set to a value
  //     mtime has already passed, which happens every time an interrupt is set
  //     up late.  There is no edge detect and no pending flop in this module --
  //     the interrupt is cleared by writing mtimecmp, not by acknowledging it.
  //
  //  7. msip.  One bit, set and cleared by software, straight through to
  //     msip_o.  The other 31 bits of that register read as zero.
  // ===========================================================================

  // ---- SCAFFOLDING -- delete as the steps above land ------------------------
  // Drives safe values so the skeleton elaborates and `make lint` stays green.
  assign lite_rsp_o = LITE_RSP_IDLE;
  assign msip_o     = 1'b0;
  assign mtip_o     = 1'b0;

  logic unused_ok;
  assign unused_ok = clk_i | rst_ni | rtc_tick_i | (|lite_req_i)
                   | (ADDR_W != 0) | (REG_DW != 0);

endmodule
