// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0

module tb_meds_s1_timer_core;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i <= ~clk_i;

  logic [11:0] addr;
  logic we;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic err;
  logic irq;

  int unsigned checks = 0;

  meds_s1_timer_core dut (
    .clk_i,
    .rst_ni,
    .reg_addr_i(addr),
    .reg_we_i(we),
    .reg_wdata_i(wdata),
    .reg_wstrb_i(wstrb),
    .reg_rdata_o(rdata),
    .reg_err_o(err),
    .timer_irq_o(irq)
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

  task automatic reset_dut;
    @(negedge clk_i);
    rst_ni = 1'b0;
    we = 1'b0;
    wstrb = '0;
    repeat (3) @(negedge clk_i);
    rst_ni = 1'b1;
  endtask

  initial begin
    repeat (2000) @(posedge clk_i);
    $fatal(1, "Timer core test timeout");
  end

  initial begin
    addr = '0;
    we = 1'b0;
    wdata = '0;
    wstrb = '0;

    reset_dut();

    read_check("reset control", 'h00, 0);
    read_check("reset compare", 'h04, 0);
    read_check("reset count", 'h08, 0);

    write_reg('h04, 32'h11223344);
    write_reg('h04, 32'haabbccdd, 4'b0101);
    read_check("partial compare write", 'h04, 32'h11bb33dd);

    write_reg('h04, 0, 4'b0000);
    read_check("zero-strobe compare", 'h04, 32'h11bb33dd);

    write_reg('h00, 1, 4'b0010);
    read_check("CTRL ignores upper-byte strobe", 'h00, 0);

    write_reg('h20, '1);
    read_check("unmapped address", 'h20, 0, 1'b1);
    read_check("invalid write preserves control", 'h00, 0);

    reset_dut();

    write_reg('h04, 3);
    write_reg('h00, 1);

    // With compare=3, the current-count comparison triggers on counting edge 4.
    repeat (3) @(negedge clk_i);
    check32("periodic not early", {31'b0, irq}, 0);

    @(negedge clk_i);
    check32("periodic event", {31'b0, irq}, 1);

    addr = 'h08;
    #1;
    check32("periodic resets count", rdata, 0);

    write_reg('h00, 0);
    write_reg('h00, 4);
    check32("IRQ clear", {31'b0, irq}, 0);

    reset_dut();

    write_reg('h04, 2);
    write_reg('h00, 3);

    repeat (3) @(negedge clk_i);
    check32("one-shot IRQ", {31'b0, irq}, 1);

    read_check("one-shot disabled", 'h00, 6);
    read_check("one-shot clears count", 'h08, 0);

    // Clear the old interrupt while retaining one-shot mode, then rearm.
    write_reg('h00, 6);
    write_reg('h00, 3);
    repeat (2) @(negedge clk_i);
    check32("rearmed one-shot not early", {31'b0, irq}, 0);
    @(negedge clk_i);
    check32("rearmed one-shot event", {31'b0, irq}, 1);
    read_check("rearmed one-shot count zero", 'h08, 0);
    read_check("rearmed one-shot disabled", 'h00, 6);

    write_reg('h00, 4);
    repeat (5) @(negedge clk_i);
    check32("disabled timer does not retrigger", {31'b0, irq}, 0);

    reset_dut();

    write_reg('h04, 0);
    write_reg('h00, 1);

    @(negedge clk_i);
    check32("compare-zero event", {31'b0, irq}, 1);

    write_reg('h00, 5);
    check32("event wins simultaneous clear", {31'b0, irq}, 1);

    write_reg('h00, 0);
    write_reg('h00, 4);
    check32("clear after disabling", {31'b0, irq}, 0);

    // Periodic mode remains enabled across multiple count clears.
    reset_dut();
    write_reg('h04, 3);
    write_reg('h00, 1);
    repeat (4) @(negedge clk_i);
    addr = 'h08;
    #1;
    check32("first periodic boundary", rdata, 0);
    // Clear pending without changing EN; this write lands before next expiry.
    write_reg('h00, 5);
    check32("periodic clear between events", {31'b0, irq}, 0);
    repeat (2) @(negedge clk_i);
    addr = 'h08;
    #1;
    check32("second periodic boundary", rdata, 0);
    check32("second periodic IRQ", {31'b0, irq}, 1);
    addr = 'h00;
    #1;
    check32("periodic remains enabled", rdata, 5);

    // A one-shot expiry wins against a same-edge enable/mode write and W1C.
    reset_dut();
    write_reg('h04, 2);
    write_reg('h00, 3);
    @(negedge clk_i);
    // write_reg presents CTRL while count is 2, for the expiry edge.
    write_reg('h00, 5);
    addr = 'h00;
    #1;
    check32("one-shot halt wins CTRL write", rdata, 6);
    addr = 'h08;
    #1;
    check32("one-shot simultaneous write clears count", rdata, 0);
    check32("one-shot event wins W1C", {31'b0, irq}, 1);

    // Equality comparison: a reduced threshold below count must not act as >=.
    reset_dut();
    write_reg('h04, 20);
    write_reg('h00, 1);
    repeat (5) @(negedge clk_i);
    write_reg('h04, 1);
    repeat (3) @(negedge clk_i);
    check32("lower threshold does not expire immediately", {31'b0, irq}, 0);
    write_reg('h00, 0);
    addr = 'h08;
    #1;
    begin
      logic [31:0] held_count;
      held_count = rdata;
      write_reg('h08, '1);
      read_check("COUNT is read only", 'h08, held_count);
      repeat (3) @(negedge clk_i);
      check32("disabled count holds", rdata, held_count);
    end

    // One-shot with zero compare expires once and stays at zero.
    reset_dut();
    write_reg('h00, 3);
    @(negedge clk_i);
    addr = 'h08;
    #1;
    check32("zero one-shot count", rdata, 0);
    read_check("zero one-shot halted with IRQ", 'h00, 6);
    write_reg('h00, 6);
    repeat (3) @(negedge clk_i);
    check32("zero one-shot does not retrigger", {31'b0, irq}, 0);

    $display("=== PASS : %0d checks ===", checks);
    $finish;
  end

endmodule
