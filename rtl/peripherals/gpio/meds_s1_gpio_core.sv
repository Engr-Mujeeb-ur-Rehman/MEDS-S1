// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
// [WIP -- M-03]
// Eight-pin GPIO register file and datapath, independent of AXI.
// Contract: docs/modules/meds_s1_gpio_core.md

module meds_s1_gpio_core #(
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

  inout  logic [7:0]        gpio_pin_io,
  output logic [7:0]        gpio_irq_o
);

  localparam logic [ADDR_W-1:0] DIR_OFFSET  = 'h00;
  localparam logic [ADDR_W-1:0] DATA_OFFSET = 'h04;
  localparam logic [ADDR_W-1:0] IRQ_OFFSET  = 'h08;

  logic [7:0] direction_q;
  logic [7:0] output_q;
  logic [7:0] synchronized_input;
  logic [7:0] previous_input_q;

  logic [7:0] edge_event;
  logic [7:0] irq_clear;
  logic write_low_byte;

  initial begin
    if (ADDR_W < 4)
      $fatal(1, "GPIO ADDR_W must be at least 4");
  end

  meds_s1_gpio_sync u_input_sync (
    .clk_i,
    .rst_ni,
    .async_i(gpio_pin_io),
    .sync_o(synchronized_input)
  );

  assign write_low_byte =
      reg_we_i && !reg_err_o && reg_wstrb_i[0];

  assign irq_clear =
      write_low_byte && reg_addr_i == IRQ_OFFSET
      ? reg_wdata_i[7:0] : 8'h00;

  // Preserve the existing both-edge behavior.
  assign edge_event = synchronized_input ^ previous_input_q;

  for (genvar pin = 0; pin < 8; pin++) begin : gen_pins
    assign gpio_pin_io[pin] =
        direction_q[pin] ? output_q[pin] : 1'bz;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      direction_q      <= '0;
      output_q         <= '0;
      previous_input_q <= '0;
      gpio_irq_o       <= '0;

    end else begin
      previous_input_q <= synchronized_input;

      // A new edge wins a simultaneous clear of the same bit.
      gpio_irq_o <= (gpio_irq_o & ~irq_clear) | edge_event;

      if (write_low_byte) begin
        case (reg_addr_i)
          DIR_OFFSET:
            direction_q <= reg_wdata_i[7:0];

          DATA_OFFSET:
            output_q <= reg_wdata_i[7:0];

          default: ;
        endcase
      end
    end
  end

  always_comb begin
    reg_rdata_o = '0;
    reg_err_o   = 1'b0;

    case (reg_addr_i)
      DIR_OFFSET:
        reg_rdata_o = {24'b0, direction_q};

      DATA_OFFSET:
        reg_rdata_o = {24'b0, synchronized_input};

      IRQ_OFFSET:
        reg_rdata_o = {24'b0, gpio_irq_o};

      default:
        reg_err_o = 1'b1;
    endcase
  end

  // Upper write bytes are reserved for this eight-bit peripheral.
  logic unused_ok;
  assign unused_ok =
      (|reg_wdata_i[31:8]) | (|reg_wstrb_i[3:1]);

endmodule
