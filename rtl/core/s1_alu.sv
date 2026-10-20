// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_alu : integer ALU and branch comparator          [COMPLETE -- REFERENCE]
//
// This module is the house-style worked reference.  It is small enough to read
// in one sitting and it demonstrates every convention the coding standard asks
// for.  Copy its shape, not its contents:
//
//   * one clocked process or none -- this one is purely combinational
//   * every output assigned on every path (no inferred latch)
//   * a unique case on an enum, with a pre-assigned default (R-C3)
//   * parameters, never magic numbers
//   * the interface contract written down in rtl/core/README.md
//
// Reference: SPEC section 7.3.  Testbench: verif/unit/tb_s1_alu.sv.
// =============================================================================

module s1_alu
  import s1_pkg::*;
#(
  parameter int unsigned WIDTH = XLEN
) (
  input  alu_op_e          op_i,
  input  cmp_op_e          cmp_op_i,
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,

  output logic [WIDTH-1:0] result_o,
  output logic             cmp_result_o
);

  // ---------------------------------------------------------------------------
  // Shared adder.  Subtraction is addition of the two's complement; sharing one
  // adder keeps the critical path to a single carry chain rather than two.
  // ---------------------------------------------------------------------------
  logic                 sub;
  logic [WIDTH-1:0]     b_eff;
  logic [WIDTH-1:0]     sum;

  always_comb begin
    unique case (op_i)
      ALU_SUB, ALU_SUBW, ALU_SLT, ALU_SLTU: sub = 1'b1;
      default:                              sub = 1'b0;
    endcase
  end

  assign b_eff = sub ? (~b_i + {{WIDTH-1{1'b0}}, 1'b1}) : b_i;
  assign sum   = a_i + b_eff;

  // ---------------------------------------------------------------------------
  // Comparison.  Computed from the operands directly rather than from the adder
  // result: the adder is already on the critical path and these are cheap.
  // ---------------------------------------------------------------------------
  logic eq, lt_signed, lt_unsigned;

  assign eq          = (a_i == b_i);
  assign lt_signed   = ($signed(a_i)   < $signed(b_i));
  assign lt_unsigned = ($unsigned(a_i) < $unsigned(b_i));

  always_comb begin
    // Default first: Verilator cannot prove enum coverage of a `unique case`,
    // and neither can a synthesiser.  Assigning up front makes the no-latch
    // property structural instead of an argument.  CODING_STANDARD.md R-C3.
    cmp_result_o = 1'b0;
    unique case (cmp_op_i)
      CMP_EQ:  cmp_result_o = eq;
      CMP_NE:  cmp_result_o = ~eq;
      CMP_LT:  cmp_result_o = lt_signed;
      CMP_GE:  cmp_result_o = ~lt_signed;
      CMP_LTU: cmp_result_o = lt_unsigned;
      CMP_GEU: cmp_result_o = ~lt_unsigned;
      CMP_NONE: cmp_result_o = 1'b0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Shifts.
  //
  // RV64 uses shamt[5:0] for the 64-bit forms and shamt[4:0] for the W forms.
  // The W forms operate on the low 32 bits and sign-extend the 32-bit result --
  // note that SRLW shifts in zeros from bit 31, not bit 63, which is the bug
  // every first implementation has.
  // ---------------------------------------------------------------------------
  localparam int unsigned SHAMT_W  = $clog2(WIDTH);
  localparam int unsigned SHAMT_WW = 5;

  logic [SHAMT_W-1:0]  shamt;
  logic [SHAMT_WW-1:0] shamt_w;
  logic [31:0]         a_w;

  assign shamt   = b_i[SHAMT_W-1:0];
  assign shamt_w = b_i[SHAMT_WW-1:0];
  assign a_w     = a_i[31:0];

  logic [WIDTH-1:0] sll_res, srl_res, sra_res;
  logic [31:0]      sllw_res, srlw_res, sraw_res;

  assign sll_res  = a_i << shamt;
  assign srl_res  = a_i >> shamt;
  assign sra_res  = $unsigned($signed(a_i) >>> shamt);
  assign sllw_res = a_w << shamt_w;
  assign srlw_res = a_w >> shamt_w;
  assign sraw_res = $unsigned($signed(a_w) >>> shamt_w);

  // ---------------------------------------------------------------------------
  // Result mux.  `unique case` covers the enum; the pre-assigned default is what
  // makes the no-latch property structural rather than an argument about
  // reachability.  Both are required -- see CODING_STANDARD.md R-C3.
  // ---------------------------------------------------------------------------
  always_comb begin
    result_o = sum;                       // default: see CODING_STANDARD.md R-C3
    unique case (op_i)
      ALU_ADD, ALU_SUB: result_o = sum;
      ALU_SLL:          result_o = sll_res;
      ALU_SLT:          result_o = {{WIDTH-1{1'b0}}, lt_signed};
      ALU_SLTU:         result_o = {{WIDTH-1{1'b0}}, lt_unsigned};
      ALU_XOR:          result_o = a_i ^ b_i;
      ALU_SRL:          result_o = srl_res;
      ALU_SRA:          result_o = sra_res;
      ALU_OR:           result_o = a_i | b_i;
      ALU_AND:          result_o = a_i & b_i;
      ALU_ADDW,
      ALU_SUBW:         result_o = {{WIDTH-32{sum[31]}},      sum[31:0]};
      ALU_SLLW:         result_o = {{WIDTH-32{sllw_res[31]}}, sllw_res};
      ALU_SRLW:         result_o = {{WIDTH-32{srlw_res[31]}}, srlw_res};
      ALU_SRAW:         result_o = {{WIDTH-32{sraw_res[31]}}, sraw_res};
      ALU_PASS_B:       result_o = b_i;
    endcase
  end

endmodule
