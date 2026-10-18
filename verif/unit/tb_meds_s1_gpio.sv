// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//

module tb_meds_s1_gpio
  import meds_s1_lite_pkg::*;
;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i <= ~clk_i;

  lite_req_t lite_req;
  lite_rsp_t lite_rsp;
  tri [7:0] gpio_pin;
  logic pin_drive_en;
  logic [7:0] pin_drive;
  logic [7:0] gpio_irq;
  int unsigned checks = 0;
  int unsigned errors = 0;

  assign gpio_pin = pin_drive_en ? pin_drive : 8'bz;

  meds_s1_gpio dut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .lite_req_i  (lite_req),
    .lite_rsp_o  (lite_rsp),
    .gpio_pin_io (gpio_pin),
    .gpio_irq_o  (gpio_irq)
  );

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  task automatic check32(input string name, input logic [31:0] got,
                         input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-28s got=0x%08h exp=0x%08h", name, got, exp);
    end
  endtask

  task automatic write_reg(input logic [3:0] addr, input logic [31:0] data);
    lite_req.valid = 1'b1;
    lite_req.write = 1'b1;
    lite_req.addr = addr;
    lite_req.wdata = data;
    lite_req.wstrb = '1;
    lite_req.rsp_ready = 1'b1;
    @(posedge clk_i);
    #1;
    lite_req = '0;
  endtask

  task automatic read_reg(input string name, input logic [3:0] addr,
                          input logic [31:0] exp);
    lite_req.valid = 1'b1;
    lite_req.write = 1'b0;
    lite_req.addr = addr;
    lite_req.wstrb = '0;
    lite_req.rsp_ready = 1'b1;
    #1;
    check1({name, " valid"}, lite_rsp.valid, 1'b1);
    check1({name, " ready"}, lite_rsp.ready, 1'b1);
    check1({name, " error"}, lite_rsp.err, 1'b0);
    check32(name, lite_rsp.rdata, exp);
    @(posedge clk_i);
    #1;
    lite_req = '0;
  endtask

  task automatic clocks(input int unsigned count);
    repeat (count) @(posedge clk_i);
    #1;
  endtask

  initial begin
    lite_req = '0;
    pin_drive_en = 1'b1;
    pin_drive = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    clocks(1);

    read_reg("reset direction", 4'h0, 32'h0);
    read_reg("reset input", 4'h4, 32'h0);
    read_reg("reset irq", 4'h8, 32'h0);
    read_reg("invalid address", 4'hc, 32'h0);

    write_reg(4'h0, 32'hff);
    write_reg(4'h4, 32'ha5);
    check32("output direction", {24'b0, gpio_pin}, 32'h000000a5);
    check32("output value", {24'b0, gpio_pin}, 32'h000000a5);

    write_reg(4'h0, 32'h0);
    clocks(3);
    write_reg(4'h8, 32'hff);
    pin_drive = 8'h81;
    clocks(3);
    read_reg("synchronized high input", 4'h4, 32'h81);
    check32("rising edge irq", {24'b0, gpio_irq}, 32'h00000081);

    write_reg(4'h8, 32'h1);
    check32("selected irq clear", {24'b0, gpio_irq}, 32'h00000080);
    pin_drive = 8'h0;
    clocks(3);
    check32("falling edge irq", {24'b0, gpio_irq}, 32'h00000081);

    write_reg(4'h8, 32'h0);
    check32("clear requires selected bits", {24'b0, gpio_irq}, 32'h00000081);
    write_reg(4'h8, 32'hff);
    check32("clear all irq bits", {24'b0, gpio_irq}, 32'h0);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_gpio failed");
    end
  end

endmodule
