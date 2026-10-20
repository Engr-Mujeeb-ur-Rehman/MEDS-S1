// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_sram : the single-port SRAM wrapper                       [COMPLETE]
//
// NORMATIVE (INTERFACES.md section 8, SPEC section 17):
//
//   No memory anywhere in MEDS-S1 may be inferred directly.  Every array --
//   register file, cache tags, cache data, TLB, VRF, any FIFO deeper than 32
//   entries -- is instantiated through this wrapper.  Enforced at review and by
//   scripts/check_structure.py.
//
//   Read latency is ONE CYCLE, REGISTERED OUTPUT, EVERYWHERE.  No exceptions.
//   A mixed-latency memory system is where timing closure and verification both
//   go to die.
//
// Why the rule exists: it is what keeps an ASIC port possible without a
// rewrite, and it costs nothing today.
//
// IMPL selects the backing store:
//   0  behavioural   -- simulation (this file)
//   1  FPGA BRAM     -- xpm_memory_spram or equivalent          [TODO: R-03]
//   2  ASIC macro    -- foundry compiler output                 [TODO: when funded]
// =============================================================================

module meds_s1_sram #(
  parameter int unsigned DW    = 64,
  parameter int unsigned DEPTH = 1024,
  parameter int unsigned IMPL  = 0,
  // derived -- do not override
  parameter int unsigned AW    = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  input  logic            req_i,
  input  logic            we_i,
  input  logic [AW-1:0]   addr_i,
  input  logic [DW/8-1:0] be_i,
  input  logic [DW-1:0]   wdata_i,
  output logic [DW-1:0]   rdata_o     // valid one cycle after req_i
);

  if (IMPL != 0) begin : g_unsupported
    // A clear elaboration-time failure beats silently synthesising the
    // behavioural model into a bitstream.
    $error("meds_s1_sram: IMPL=%0d not implemented yet (see header)", IMPL);
  end

  logic [DW-1:0] mem [DEPTH];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= '0;
    end else begin
      if (req_i) begin
        if (we_i) begin
          for (int unsigned b = 0; b < DW/8; b++) begin
            if (be_i[b]) mem[addr_i][b*8 +: 8] <= wdata_i[b*8 +: 8];
          end
        end
        // Read-during-write returns the OLD contents.  Stated, not accidental:
        // consumers that need write-forwarding must build it themselves.
        rdata_o <= mem[addr_i];
      end
    end
  end

endmodule
