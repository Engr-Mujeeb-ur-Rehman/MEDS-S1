// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_pkg : MEDS-S1 core parameters and shared types                [COMPLETE]
//
// Every type the core passes between modules lives here.  Nothing in rtl/core/
// declares a struct of its own -- if two modules need to agree on a shape, that
// shape belongs in this file.
//
// Reference: SPEC Part II, INTERFACES.md sections 1 and 2.
// =============================================================================

package s1_pkg;

  // ---------------------------------------------------------------------------
  // Global parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned XLEN      = 64;
  parameter int unsigned ILEN      = 32;
  parameter int unsigned PLEN      = 40;   // physical address width
  parameter int unsigned REG_ADDR_W = 5;

  parameter int unsigned CB_DEPTH  = 8;    // completion buffer entries (SPEC 9.3)
  parameter int unsigned CB_IDX_W  = $clog2(CB_DEPTH);
  parameter int unsigned MXIF_ID_W = 4;    // INTERFACES.md 1.3

  parameter int unsigned PMP_N     = 16;

  // Reset vector.  Overridable per config; the boot ROM lives here.
  parameter logic [XLEN-1:0] BOOT_ADDR = 64'h0000_0000_0000_1000;

  // ---------------------------------------------------------------------------
  // Privilege levels
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
  } priv_lvl_e;

  // ---------------------------------------------------------------------------
  // ALU
  //
  // The W-suffixed operations are the RV64 32-bit forms: compute on the low 32
  // bits and sign-extend the result.  Keeping them as distinct opcodes rather
  // than a width flag keeps the decoder flat.
  // ---------------------------------------------------------------------------
  typedef enum logic [4:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
    ALU_ADDW, ALU_SUBW, ALU_SLLW, ALU_SRLW, ALU_SRAW,
    ALU_PASS_B                      // LUI and friends: forward operand b
  } alu_op_e;

  // Branch conditions, evaluated by the ALU comparator.
  typedef enum logic [2:0] {
    CMP_NONE, CMP_EQ, CMP_NE, CMP_LT, CMP_GE, CMP_LTU, CMP_GEU
  } cmp_op_e;

  // ---------------------------------------------------------------------------
  // Where a completed instruction's result came from
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    UNIT_ALU, UNIT_LSU, UNIT_MUL, UNIT_DIV, UNIT_CSR, UNIT_MXIF, UNIT_NONE
  } exec_unit_e;

  // ---------------------------------------------------------------------------
  // Completion buffer entry (SPEC 9.1)
  //
  // `norollback` is 1 for every main-pipe instruction and is driven by the
  // coprocessor for MXIF instructions -- it is the field that lets a long vector
  // operation retire while it is still executing (INTERFACES.md R1.9).
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic                   valid;
    logic                   done;
    logic                   norollback;
    logic [XLEN-1:0]        pc;
    logic [ILEN-1:0]        instr;
    logic [REG_ADDR_W-1:0]  rd;
    logic                   rd_we;
    logic [XLEN-1:0]        result;
    logic                   exc;
    logic [5:0]             exccode;
    logic [XLEN-1:0]        exctval;
    logic                   is_mxif;
    logic [MXIF_ID_W-1:0]   mxif_id;
    exec_unit_e             unit;
  } cb_entry_t;

  // ---------------------------------------------------------------------------
  // Standard exception codes (mcause, interrupt bit clear)
  // ---------------------------------------------------------------------------
  parameter logic [5:0] EXC_INSTR_ADDR_MISALIGNED = 6'd0;
  parameter logic [5:0] EXC_INSTR_ACCESS_FAULT    = 6'd1;
  parameter logic [5:0] EXC_ILLEGAL_INSTR         = 6'd2;
  parameter logic [5:0] EXC_BREAKPOINT            = 6'd3;
  parameter logic [5:0] EXC_LOAD_ADDR_MISALIGNED  = 6'd4;
  parameter logic [5:0] EXC_LOAD_ACCESS_FAULT     = 6'd5;
  parameter logic [5:0] EXC_STORE_ADDR_MISALIGNED = 6'd6;
  parameter logic [5:0] EXC_STORE_ACCESS_FAULT    = 6'd7;
  parameter logic [5:0] EXC_ECALL_U               = 6'd8;
  parameter logic [5:0] EXC_ECALL_S               = 6'd9;
  parameter logic [5:0] EXC_ECALL_M               = 6'd11;
  parameter logic [5:0] EXC_INSTR_PAGE_FAULT      = 6'd12;
  parameter logic [5:0] EXC_LOAD_PAGE_FAULT       = 6'd13;
  parameter logic [5:0] EXC_STORE_PAGE_FAULT      = 6'd15;

  // ---------------------------------------------------------------------------
  // Physical memory attributes (SPEC section 11, INTERFACES.md P1-P5)
  //
  // Generated into pma_decode.sv from soc.yaml; this is the shape it produces.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic       cacheable;
    logic       idempotent;
    logic       strong_order;   // 1 = strongly-ordered I/O, 0 = RVWMO
    logic       atomic_lrsc;
    logic       atomic_amo;
    logic       align_natural;  // 1 = misaligned access faults
  } pma_t;

  // ---------------------------------------------------------------------------
  // MEM-REQ protocol payloads (INTERFACES.md section 2)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [XLEN-1:0]      addr;
    logic                 we;
    logic [XLEN/8-1:0]    be;
    logic [XLEN-1:0]      wdata;
    logic [2:0]           size;   // log2 bytes
    priv_lvl_e            mode;
    logic [3:0]           id;
  } mem_req_t;

  typedef struct packed {
    logic [3:0]           id;
    logic [XLEN-1:0]      rdata;
    logic                 err;
    logic [1:0]           errcode;
  } mem_rsp_t;

endpackage
