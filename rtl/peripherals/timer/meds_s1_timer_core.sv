// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
// [WIP -- M-03]
// Timer register file and datapath, independent of AXI.
// Contract: docs/modules/meds_s1_timer_core.md

module meds_s1_timer_core #(
  parameter int unsigned ADDR_W = 12
) (
  input  logic              clk_i,
  input  logic              rst_ni,

  input  logic [ADDR_W-1:0] reg_addr_i,
  input  logic              reg_we_i,
  input  logic [31:0]       reg_wdata_i,
  input  logic [3:0]        reg_wstrb_i,
  output logic [31:0]       reg_rdata_o,
  output logic              reg_err_o,

  output logic              timer_irq_o
);

  localparam logic [ADDR_W-1:0] CTRL_OFFSET    = 'h00;
  localparam logic [ADDR_W-1:0] COMPARE_OFFSET = 'h04;
  localparam logic [ADDR_W-1:0] COUNT_OFFSET   = 'h08;

  logic enabled_q;
  logic oneshot_q;
  logic [31:0] compare_q;
  logic [31:0] count_q;

  logic control_write;
  logic compare_write;
  logic irq_clear;
  logic action;
  logic oneshot_halt;

  initial begin
    if (ADDR_W < 4)
      $fatal(1, "Timer ADDR_W must be at least 4");
  end

  assign control_write =
      reg_we_i && !reg_err_o &&
      reg_addr_i == CTRL_OFFSET &&
      reg_wstrb_i[0];

  assign compare_write =
      reg_we_i && !reg_err_o &&
      reg_addr_i == COMPARE_OFFSET;

  assign irq_clear = control_write && reg_wdata_i[2];

  assign action = enabled_q && count_q >= compare_q;
  assign oneshot_halt = oneshot_q && action;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enabled_q <= 1'b0;
      oneshot_q <= 1'b0;

    end else if (oneshot_halt) begin
      // Preserve the original priority over a simultaneous CTRL write.
      enabled_q <= 1'b0;

    end else if (control_write) begin
      enabled_q <= reg_wdata_i[0];
      oneshot_q <= reg_wdata_i[1];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      compare_q <= '0;

    end else if (compare_write) begin
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (reg_wstrb_i[byte_idx]) begin
          compare_q[byte_idx*8 +: 8]
              <= reg_wdata_i[byte_idx*8 +: 8];
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= '0;

    end else if (enabled_q) begin
      if (!oneshot_q && action)
        count_q <= '0;
      else
        count_q <= count_q + 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      timer_irq_o <= 1'b0;
    else if (action)
      timer_irq_o <= 1'b1;
    else if (irq_clear)
      timer_irq_o <= 1'b0;
  end

  always_comb begin
    reg_rdata_o = '0;
    reg_err_o   = 1'b0;

    case (reg_addr_i)
      CTRL_OFFSET:
        reg_rdata_o =
            {29'b0, timer_irq_o, oneshot_q, enabled_q};

      COMPARE_OFFSET:
        reg_rdata_o = compare_q;

      COUNT_OFFSET:
        reg_rdata_o = count_q;

      default:
        reg_err_o = 1'b1;
    endcase
  end

endmodule
