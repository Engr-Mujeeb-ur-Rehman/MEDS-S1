// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0

module tb_meds_s1_gpio_core;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i <= ~clk_i;

  logic [11:0] addr;
  logic we;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic err;

  tri [7:0] pins;
  logic drive_enable;
  logic [7:0] external_value;
  logic [7:0] irq;

  int unsigned checks = 0;

  assign pins = drive_enable ? external_value : 8'bz;

  meds_s1_gpio_core dut (
    .clk_i,
    .rst_ni,
    .reg_addr_i(addr),
    .reg_we_i(we),
    .reg_wdata_i(wdata),
    .reg_wstrb_i(wstrb),
    .reg_rdata_o(rdata),
    .reg_err_o(err),
    .gpio_pin_io(pins),
    .gpio_irq_o(irq)
  );

  task automatic check32(
    input string name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    checks++;
    if (got !== expected)
      $fatal(1, "%s: got=%h expected=%h", name, got, expected);
  endtask

  task automatic write_reg(
    input logic [11:0] address,
    input logic [31:0] data,
    input logic [3:0] strobes = 4'hf
  );
    @(negedge clk_i);
    addr = address;
    wdata = data;
    wstrb = strobes;
    we = 1'b1;

    @(negedge clk_i);
    we = 1'b0;
    wstrb = '0;
  endtask

  task automatic read_check(
    input string name,
    input logic [11:0] address,
    input logic [31:0] expected,
    input logic expected_error = 1'b0
  );
    @(negedge clk_i);
    addr = address;
    #1;
    check32(name, rdata, expected);
    check32({name, " error"}, {31'b0, err},
            {31'b0, expected_error});
  endtask

  initial begin
    repeat (2000) @(posedge clk_i);
    $fatal(1, "GPIO core test timeout");
  end

  initial begin
    addr = '0;
    we = 1'b0;
    wdata = '0;
    wstrb = '0;
    drive_enable = 1'b1;
    external_value = '0;

    repeat (4) @(negedge clk_i);
    rst_ni = 1'b1;

    read_check("reset direction", 'h00, 0);
    read_check("reset input", 'h04, 0);
    read_check("reset pending", 'h08, 0);

    // Release the external driver before switching pins to output.
    @(negedge clk_i);
    drive_enable = 1'b0;

    write_reg('h04, 'ha5);
    write_reg('h00, 'hff);
    check32("output value", {24'b0, pins}, 'ha5);

    write_reg('h04, 0, 4'b0000);
    check32("zero-strobe ignored", {24'b0, pins}, 'ha5);

    write_reg('h04, 0, 4'b0010);
    check32("reserved-byte ignored", {24'b0, pins}, 'ha5);

    write_reg('h00, 0);

    @(negedge clk_i);
    drive_enable = 1'b1;
    external_value = 0;

    repeat (5) @(negedge clk_i);
    write_reg('h08, 'hff);

    @(negedge clk_i);
    external_value = 'h81;

    repeat (4) @(negedge clk_i);
    read_check("synchronized input", 'h04, 'h81);
    check32("rising IRQ", {24'b0, irq}, 'h81);

    write_reg('h08, 1);
    check32("selective clear", {24'b0, irq}, 'h80);

    @(negedge clk_i);
    external_value = 0;

    repeat (4) @(negedge clk_i);
    check32("falling IRQ", {24'b0, irq}, 'h81);

    write_reg('h08, 0);
    check32("zero data does not clear", {24'b0, irq}, 'h81);

    write_reg('h08, 'hff);
    check32("clear all", {24'b0, irq}, 0);

    // Arrange a new synchronized edge and a clear on the same edge.
    @(negedge clk_i);
    external_value = 1;

    repeat (2) @(negedge clk_i);
    addr = 'h08;
    wdata = 1;
    wstrb = 4'h1;
    we = 1'b1;

    @(negedge clk_i);
    we = 1'b0;
    wstrb = '0;
    check32("new edge wins clear", {24'b0, irq}, 1);

    read_check("unmapped offset", 'h20, 0, 1'b1);

    write_reg('h20, 'hff);
    read_check("unmapped write preserves direction", 'h00, 0);

    $display("=== PASS : %0d checks ===", checks);
    $finish;
  end

endmodule

