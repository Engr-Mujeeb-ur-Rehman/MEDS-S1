// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_plic : platform-level interrupt controller           [SKELETON -- T-05]
//
// Multiplexes every peripheral and accelerator interrupt into the core's
// external-interrupt line: priority, pending, enable, threshold, and the
// claim/complete handshake that makes an interrupt serviced exactly once.
//
// ALL sources are LEVEL-SENSITIVE (SPEC section 24).  There is no edge detect
// anywhere in this module and there must never be one: an edge crossing the
// socket CDC is how interrupts get lost, and removing that bug class is the
// whole reason the platform made the rule.
//
// MEDS-S1 is single-hart and M-mode only, so there is ONE target context.  No
// target index, no 0x1000 context stride to walk.  When s1_linux eventually
// needs an S-mode context this file gains a second one; say so in the module
// page rather than pre-building it (ADR-0005).
//
// The PORT LIST below is frozen.  The BODY is yours.  Read meds_s1_clint.sv
// first -- it is the smaller of the two and the shell is identical.
//
// REG_DW is 32 here, not 64: every register in the PLIC specification is 32
// bits.  meds_s1_lite_regif absorbs the byte lane, so this module never sees
// the upper half of the bus and is what it would be on a 32-bit bus.  That is
// the whole reason the adapter is parameterised.
//
// Reference: RISC-V PLIC specification v1.0, SPEC section 24, INTERFACES.md
// section 6.  Register map: docs/modules/meds_s1_plic.md -- fill it in first.
// Testbench: verif/unit/tb_meds_s1_plic.sv  <- you write this.
// =============================================================================

module meds_s1_plic
  import meds_s1_lite_pkg::*;
#(
  // Source 0 is reserved by the specification as "no interrupt" and is never
  // allocated, so N_SOURCES counts it: 16 means sources 1..15 are usable.  The
  // value comes from the interrupt allocation in soc.yaml (SPEC section 24).
  parameter int unsigned N_SOURCES = 16,
  parameter int unsigned PRIO_W    = 3
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  // Level-sensitive interrupt lines, synchronous to clk_i.  Any CDC belongs in
  // the accelerator socket (SPEC section 20.1), never here.  irq_i[0] is tied
  // off: source 0 does not exist.
  input  logic [N_SOURCES-1:0] irq_i,

  // ---- the frozen I4 bus port.  Do not add signals here. --------------------
  input  lite_req_t            lite_req_i,
  output lite_rsp_t            lite_rsp_o,

  // ---- external interrupt to the core's mip CSR -----------------------------
  output logic                 meip_o
);

  // 4 MiB window, from the `plic` region in configs/*.yaml.
  localparam int unsigned ADDR_W = 22;
  localparam int unsigned REG_DW = 32;

  // ===========================================================================
  // TODO(T-05) -- everything below.  Steps 1 and 2 are the same shell as CLINT;
  // do that module first and this part is half an hour.
  //
  //  1. BUS ADAPTER.  Declare the register-file wires and instantiate
  //     meds_s1_lite_regif with .ADDR_W(ADDR_W) and .REG_DW(REG_DW).
  //
  //  2. REGISTER STORAGE.  priority (PRIO_W bits per source), pending and
  //     enable (one bit per source), threshold.
  //
  //     Declare these PACKED.  `logic [PRIO_W-1:0] prio_q [N_SOURCES];` -- an
  //     unpacked array -- is rejected by scripts/check_structure.py rule S7,
  //     which requires every memory to sit behind meds_s1_sram.  These are
  //     flops, not a memory, and you want them packed anyway because the
  //     priority reduction in step 5 reads all of them in one cycle.
  //
  //  3. THE GATEWAY.  A level gateway sets pending while the source is high and
  //     clears it when the source is claimed.  It is not an edge detector and it
  //     does not latch: if the line is still high after a claim, pending must
  //     re-arm by itself.  Source 0 never becomes pending.
  //
  //     What happens when a claim and a fresh assertion of the same source land
  //     in the SAME cycle is the race your G0 note has to answer, and it is the
  //     first thing you will be asked at the gate review.  Answer it in the note
  //     before you write the RTL, not after.
  //
  //  4. REGISTER MAP.  Read decode and write decode, offsets from your table:
  //
  //       priority   RW, one register per source
  //       pending    RO bitfield, 32 sources per word
  //       enable     RW bitfield
  //       threshold  RW
  //       claim      RO -- reading it returns the winning source AND clears
  //                  that source's pending bit, in one indivisible access
  //       complete   WO at the same offset -- writing a source ID re-arms it
  //
  //     A `complete` naming a source that was never claimed is IGNORED, not an
  //     error.  Check the specification for that before you implement it, and
  //     record on the module page why it is right.
  //
  //  5. ARBITRATION.  The winner is the highest-priority source that is pending
  //     AND enabled AND whose priority is STRICTLY greater than the threshold.
  //     Priority 0 means "never interrupt" and must be the reset value.  When
  //     two eligible sources share the highest priority the winner is the LOWEST
  //     source ID; write the test that fails if you reverse that.  Claim returns
  //     0 when nothing qualifies -- which is what source 0 being reserved buys.
  //
  //     Watch the threshold boundary: a source whose priority EQUALS the
  //     threshold must not fire.  Read the specification sentence, do not guess.
  //
  //  6. meip_o.  A LEVEL, derived combinationally from the same condition as
  //     step 5.  It deasserts by itself once software has claimed the last
  //     qualifying source -- there is no acknowledge register.
  //
  //  7. FILE SIZE.  R-C6 caps a file at 800 lines and a PLIC with the decode
  //     written inline will approach it.  If you get close, split the gateway
  //     and arbitration from the register file rather than asking for a waiver;
  //     it is better design and the checker is telling you so.
  // ===========================================================================

  // ---- SCAFFOLDING -- delete as the steps above land ------------------------
  // Drives safe values so the skeleton elaborates and `make lint` stays green.
  assign lite_rsp_o = LITE_RSP_IDLE;
  assign meip_o     = 1'b0;

  logic unused_ok;
  assign unused_ok = clk_i | rst_ni | (|irq_i) | (|lite_req_i)
                   | (ADDR_W != 0) | (REG_DW != 0) | (PRIO_W != 0);

endmodule
