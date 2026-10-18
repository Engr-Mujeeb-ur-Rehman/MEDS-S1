// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_lite_regif : unit testbench for the I4 bus adapter [SKELETON -- T-05]
//
// The SHAPE of a MEDS-S1 unit testbench, with the tests left to you.  Copy this
// shape for tb_meds_s1_clint.sv and tb_meds_s1_plic.sv.
//
// What is given: the clock, the check helper, the watchdog and the pass/fail
// epilogue -- the mechanical parts that make CI able to tell "passed" from "did
// not run".  What is yours: a register-file model, a bus driver, and every test
// in the TODO list below.
//
// Four habits that are review items (VERIFICATION_GUIDE.md section 3):
//
//   1. Expectations come from PARAMETERS, not constants (R-V2).  The same body
//      must run against REG_DW = 32 and REG_DW = 64 and the check count should
//      rise, not the file length.
//   2. The golden model is written from the PROTOCOL, not copied from the DUT's
//      expressions.  If your expected value is the design's own expression, the
//      test proves only that the code equals itself.
//   3. Test what causes HANGS, not only wrong answers (R-V5).
//   4. Report a check COUNT and exit non-zero on failure (R-V3).  The runner
//      requires the "=== PASS" line AND exit code 0, because a testbench that
//      compiles, runs and checks nothing also exits 0.
//
// Run:  make test-unit TB=meds_s1_lite_regif
// =============================================================================

module tb_meds_s1_lite_regif
  import meds_s1_lite_pkg::*;
;

  localparam int unsigned ADDR_W = 16;
  localparam int unsigned REG_DW = 32;

  logic clk;
  logic rst_n;

  // Clock generator.  An `initial forever` rather than a bare `always`: the
  // coding standard has no bare-always form, and Verilator flags a blocking
  // assignment inside a sequential process.
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  int unsigned checks = 0;
  int unsigned errors = 0;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  lite_req_t           req;
  lite_rsp_t           rsp;
  logic [ADDR_W-1:0]   addr;
  logic                we, re, err;
  logic [REG_DW-1:0]   wdata, rdata;
  logic [REG_DW/8-1:0] wstrb;

  meds_s1_lite_regif #(
    .ADDR_W (ADDR_W),
    .REG_DW (REG_DW)
  ) dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .lite_req_i (req),
    .lite_rsp_o (rsp),
    .addr_o     (addr),
    .we_o       (we),
    .re_o       (re),
    .wdata_o    (wdata),
    .wstrb_o    (wstrb),
    .rdata_i    (rdata),
    .err_i      (err)
  );

  // ---------------------------------------------------------------------------
  // Check helpers.  Keep these -- the "=== PASS : n checks ===" contract and a
  // non-zero exit are what the runner keys on.
  // ---------------------------------------------------------------------------
  task automatic check(input string name,
                       input logic [63:0] got,
                       input logic [63:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL  %-48s got %016h  exp %016h", name, got, exp);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL  %-48s got %b  exp %b", name, got, exp);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Watchdog.  A deadlocked handshake is a hang, not a wrong answer, and a
  // testbench that hangs tells CI nothing -- it just burns the runner's budget
  // until it is killed.  Keep this from the first line you write: the bugs you
  // are hunting in a bus adapter are exactly the ones that hang.
  // ---------------------------------------------------------------------------
  initial begin
    repeat (500000) @(posedge clk);
    $fatal(1, "tb_meds_s1_lite_regif: watchdog expired -- a handshake deadlocked");
  end

  // ===========================================================================
  // TODO(T-05) -- the testbench itself.
  //
  //  A. REGISTER-FILE MODEL.  A small array behind addr_o/we_o/re_o, with err_i
  //     asserted above the last mapped offset.  Keep it trivial: the DUT is the
  //     bus adapter, and anything clever here only obscures which side failed.
  //     (Unpacked arrays are allowed in verif/, unlike in rtl/.)
  //
  //  B. BUS DRIVER.  Tasks to run one write and one read to completion.  Two
  //     things to get right, because both are hangs rather than wrong answers:
  //
  //       - retire each channel the cycle its OWN handshake completes.  A driver
  //         that holds `valid` high after a transfer waits forever for a `ready`
  //         that has already gone low.
  //       - let the caller SKEW aw and w against each other, and hold b_ready
  //         and r_ready low on demand.  Without those knobs you cannot write
  //         tests D and G below at all.
  //
  //     Once it works, lift it into verif/common/meds_s1_lite_bfm.sv -- the CLINT
  //     and PLIC testbenches and M-01..M-03 all need the same driver, and you are
  //     the second user, which is the bar for putting something in common/.
  //
  //  C. BASIC ACCESS.  Write a register, read it back, at both an even and an
  //     ODD register offset.  The odd one matters: with REG_DW = 32 on the
  //     64-bit bus it lives in the upper half of the bus word, and a lane bug
  //     reads every odd register as zero while every test on register 0 passes.
  //
  //  D. CHANNEL ORDERING.  W arriving before AW, and AW before W, with several
  //     cycles of skew each way.  W-before-AW is legal AXI4-Lite and it is the
  //     ordering a hand-written slave deadlocks on.
  //
  //  E. BYTE STROBES.  A write with only some strobes set must leave the other
  //     bytes of that register untouched.
  //
  //  F. ERRORS.  An unmapped offset must return SLVERR on both read and write.
  //     With REG_DW = 32, a write whose strobes span both lanes must return
  //     SLVERR *and* leave the register file unchanged -- check both halves of
  //     that sentence, they are different bugs.
  //
  //  G. BACKPRESSURE (R-V5).  Hold b_ready low, then r_ready low.  In each case
  //     the response `valid` must ASSERT anyway and the payload must stay stable
  //     until accepted.  Do both channels: a slave whose `valid` is a function
  //     of its own `ready` (an R-C10 violation) passes every read-side test and
  //     still deadlocks on writes.  Ask yourself which single line of the DUT you
  //     would have to change to break this, then confirm your test catches it.
  //
  //  H. RANDOM SWEEP.  A few hundred randomised accesses against a shadow model
  //     you maintain from the protocol rules.  Use $urandom -- the seeded one --
  //     and never the unseeded variant it is easily confused with (R-V4); a
  //     failure you cannot re-run is not a bug report, and check_structure.py
  //     rejects the wrong one anywhere in the file, comments included.  Seed the
  //     shadow and the device from the same state first, or you will spend an
  //     afternoon debugging your own testbench.
  //
  //  I. PARAMETER SWEEP (R-V2).  Instantiate a SECOND dut at REG_DW = 64 and run
  //     the same tests against both.  If that means copying the test body, your
  //     driver is not parameterised enough -- fix the driver, do not copy.
  //
  // When you think you are done, hand the module to your backup and ask them to
  // change ONE line of the DUT.  Your testbench must go red, and the failure
  // message must name what broke.  That five-minute exercise says more about the
  // suite than an hour of reading it, and it is what you will be asked to do at
  // the gate review.
  // ===========================================================================

  initial begin
    req   = '0;
    rdata = '0;
    err   = 1'b0;
    rst_n = 1'b0;
    repeat (4) @(negedge clk);

    // Reset state.  These four pass against the skeleton DUT and are here so
    // the file runs end to end from day one -- four checks is not a suite.
    check1("b_valid low in reset", rsp.b_valid,  1'b0);
    check1("r_valid low in reset", rsp.r_valid,  1'b0);
    check1("we low in reset",      we,           1'b0);
    check1("re low in reset",      re,           1'b0);

    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // TODO(T-05): tests A..I above go here.

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_lite_regif failed");
    end
  end

endmodule
