// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_alu : unit testbench for s1_alu               [COMPLETE -- REFERENCE]
//
// This is the template every unit testbench in MEDS-S1 copies.  Three habits it
// demonstrates, all of which are review items (VERIFICATION_GUIDE.md section 3):
//
//   1. Derive expectations from PARAMETERS, never from constants.  The same
//      testbench must run unmodified at every configuration.
//   2. Check the properties that cause HANGS, not just wrong answers.
//   3. Report a check COUNT and exit non-zero on failure, so CI can tell the
//      difference between "passed" and "did not run".
//
// Run:  make test-unit            (all testbenches)
//       make test-unit TB=s1_alu  (just this one)
// =============================================================================

module tb_s1_alu
  import s1_pkg::*;
;

  localparam int unsigned W = XLEN;

  alu_op_e          op;
  cmp_op_e          cmp_op;
  logic [W-1:0]     a, b;
  logic [W-1:0]     result;
  logic             cmp_result;

  int unsigned checks = 0;
  int unsigned errors = 0;

  s1_alu #(.WIDTH(W)) dut (
    .op_i         (op),
    .cmp_op_i     (cmp_op),
    .a_i          (a),
    .b_i          (b),
    .result_o     (result),
    .cmp_result_o (cmp_result)
  );

  // ---------------------------------------------------------------------------
  // Check helpers
  // ---------------------------------------------------------------------------
  task automatic check(input string name,
                       input logic [W-1:0] got,
                       input logic [W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-28s got=0x%016h exp=0x%016h", name, got, exp);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  // Apply an operation and settle combinational logic.
  task automatic apply(input alu_op_e o, input logic [W-1:0] x, input logic [W-1:0] y);
    op = o; cmp_op = CMP_NONE; a = x; b = y;
    #1;
  endtask

  // ---------------------------------------------------------------------------
  // Golden model.  Written from the ISA manual, independently of the DUT --
  // if it is a copy of the RTL it proves nothing.
  // ---------------------------------------------------------------------------
  function automatic logic [W-1:0] golden(input alu_op_e o,
                                          input logic [W-1:0] x,
                                          input logic [W-1:0] y);
    logic [31:0] xw, yw, rw;
    xw = x[31:0];
    yw = y[31:0];
    case (o)
      ALU_ADD:    return x + y;
      ALU_SUB:    return x - y;
      ALU_SLL:    return x << y[$clog2(W)-1:0];
      ALU_SLT:    return {{W-1{1'b0}}, ($signed(x)   < $signed(y))};
      ALU_SLTU:   return {{W-1{1'b0}}, ($unsigned(x) < $unsigned(y))};
      ALU_XOR:    return x ^ y;
      ALU_SRL:    return x >> y[$clog2(W)-1:0];
      ALU_SRA:    return $unsigned($signed(x) >>> y[$clog2(W)-1:0]);
      ALU_OR:     return x | y;
      ALU_AND:    return x & y;
      ALU_ADDW:   begin rw = xw + yw;                             return {{W-32{rw[31]}}, rw}; end
      ALU_SUBW:   begin rw = xw - yw;                             return {{W-32{rw[31]}}, rw}; end
      ALU_SLLW:   begin rw = xw << y[4:0];                        return {{W-32{rw[31]}}, rw}; end
      ALU_SRLW:   begin rw = xw >> y[4:0];                        return {{W-32{rw[31]}}, rw}; end
      ALU_SRAW:   begin rw = $unsigned($signed(xw) >>> y[4:0]);   return {{W-32{rw[31]}}, rw}; end
      ALU_PASS_B: return y;
      default:    return 'x;
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  logic [W-1:0] corner [];

  initial begin
    $display("=== tb_s1_alu : XLEN=%0d ===", W);

    // Corner values, derived from the parameter rather than hard-coded.
    corner = new[10];
    corner[0] = '0;
    corner[1] = {W{1'b1}};                      // -1
    corner[2] = {1'b0, {W-1{1'b1}}};            // INT_MAX
    corner[3] = {1'b1, {W-1{1'b0}}};            // INT_MIN
    corner[4] = 64'h0000_0000_0000_0001;
    corner[5] = 64'h0000_0000_7FFF_FFFF;        // 32-bit INT_MAX
    corner[6] = 64'h0000_0000_8000_0000;        // sign bit of the W forms
    corner[7] = 64'hFFFF_FFFF_8000_0000;
    corner[8] = 64'h0123_4567_89AB_CDEF;
    corner[9] = 64'hDEAD_BEEF_CAFE_BABE;

    // --- directed: every op against every corner pair ------------------------
    foreach (corner[i]) begin
      foreach (corner[j]) begin
        for (int unsigned o = 0; o <= int'(ALU_PASS_B); o++) begin
          alu_op_e cur = alu_op_e'(o);
          apply(cur, corner[i], corner[j]);
          check($sformatf("%s(c%0d,c%0d)", cur.name(), i, j), result, golden(cur, a, b));
        end
      end
    end

    // --- the RV64 W-form trap: SRLW must shift in zeros from bit 31 ----------
    // A 64-bit SRL on a negative 32-bit value gives a completely different
    // answer.  This is the single most common RV64 ALU bug, so it gets its own
    // named check rather than hiding inside the sweep above.
    apply(ALU_SRLW, 64'hFFFF_FFFF_8000_0000, 64'd4);
    check("SRLW zero-fill from bit31", result, 64'h0000_0000_0800_0000);

    apply(ALU_SRAW, 64'hFFFF_FFFF_8000_0000, 64'd4);
    check("SRAW sign-fill from bit31", result, 64'hFFFF_FFFF_F800_0000);

    // W-form results are always sign-extended, even when the operands are not.
    apply(ALU_ADDW, 64'h0000_0000_7FFF_FFFF, 64'd1);
    check("ADDW sign-extends overflow", result, 64'hFFFF_FFFF_8000_0000);

    // Shift amounts are masked, not saturated.
    apply(ALU_SLL, 64'd1, 64'd64);
    check("SLL shamt masked to 6 bits", result, 64'd1);
    apply(ALU_SLLW, 64'd1, 64'd32);
    check("SLLW shamt masked to 5 bits", result, 64'd1);

    // --- comparator ----------------------------------------------------------
    op = ALU_ADD;
    foreach (corner[i]) begin
      foreach (corner[j]) begin
        a = corner[i]; b = corner[j];
        cmp_op = CMP_EQ;  #1; check1("CMP_EQ",  cmp_result, a == b);
        cmp_op = CMP_NE;  #1; check1("CMP_NE",  cmp_result, a != b);
        cmp_op = CMP_LT;  #1; check1("CMP_LT",  cmp_result, $signed(a)   <  $signed(b));
        cmp_op = CMP_GE;  #1; check1("CMP_GE",  cmp_result, $signed(a)   >= $signed(b));
        cmp_op = CMP_LTU; #1; check1("CMP_LTU", cmp_result, $unsigned(a) <  $unsigned(b));
        cmp_op = CMP_GEU; #1; check1("CMP_GEU", cmp_result, $unsigned(a) >= $unsigned(b));
      end
    end

    // CMP_NONE must be quiet.  If it ever floats, every non-branch instruction
    // becomes a random branch -- a hang, not a wrong answer.
    cmp_op = CMP_NONE; a = '0; b = '0; #1;
    check1("CMP_NONE is 0", cmp_result, 1'b0);

    // --- random ---------------------------------------------------------------
    for (int unsigned n = 0; n < 2000; n++) begin
      alu_op_e cur = alu_op_e'($urandom_range(int'(ALU_PASS_B), 0));
      apply(cur, {$urandom, $urandom}, {$urandom, $urandom});
      check($sformatf("rand %s", cur.name()), result, golden(cur, a, b));
    end

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_alu failed");
    end
  end

endmodule


