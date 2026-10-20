// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
// [WIP -- M-03]
// Two-stage synchronization of independent GPIO inputs.
// Contract: docs/modules/meds_s1_gpio_sync.md

module meds_s1_gpio_sync (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic [7:0] async_i,
  output logic [7:0] sync_o
);

  (* ASYNC_REG = "TRUE" *) logic [7:0] first_q;
  (* ASYNC_REG = "TRUE" *) logic [7:0] second_q;

  assign sync_o = second_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      first_q  <= '0;
      second_q <= '0;
    end else begin
      first_q  <= async_i;
      second_q <= first_q;
    end
  end

endmodule
