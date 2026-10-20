// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
// [WIP -- M-03]
// GPIO integration wrapper using the shared T-05 register adapter.
// Contract: docs/modules/meds_s1_gpio.md

module meds_s1_gpio
  import meds_s1_lite_pkg::*;
#(
  parameter int unsigned ADDR_W = 12
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  lite_req_t  lite_req_i,
  output lite_rsp_t  lite_rsp_o,
  inout  logic [7:0] gpio_pin_io,
  output logic [7:0] gpio_irq_o
);

  logic [ADDR_W-1:0] reg_addr;
  logic reg_we;
  logic reg_re;
  logic [31:0] reg_wdata;
  logic [3:0] reg_wstrb;
  logic [31:0] reg_rdata;
  logic reg_err;

  meds_s1_lite_regif #(
    .ADDR_W(ADDR_W),
    .REG_DW(32)
  ) u_regif (
    .clk_i,
    .rst_ni,
    .lite_req_i,
    .lite_rsp_o,

    .addr_o(reg_addr),
    .we_o(reg_we),
    .re_o(reg_re),
    .wdata_o(reg_wdata),
    .wstrb_o(reg_wstrb),
    .rdata_i(reg_rdata),
    .err_i(reg_err)
  );

  meds_s1_gpio_core #(
    .ADDR_W(ADDR_W)
  ) u_core (
    .clk_i,
    .rst_ni,

    .reg_addr_i(reg_addr),
    .reg_we_i(reg_we),
    .reg_wdata_i(reg_wdata),
    .reg_wstrb_i(reg_wstrb),
    .reg_rdata_o(reg_rdata),
    .reg_err_o(reg_err),

    .gpio_pin_io,
    .gpio_irq_o
  );

  // GPIO reads have no side effects.
  logic unused_ok;
  assign unused_ok = reg_re;

endmodule
