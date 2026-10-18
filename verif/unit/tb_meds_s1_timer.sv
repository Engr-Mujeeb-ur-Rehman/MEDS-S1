// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//

module tb_meds_s1_timer
  import meds_s1_lite_pkg::*;
;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i <= ~clk_i;

  lite_req_t lite_req;
  lite_rsp_t lite_rsp;
  logic timer_irq;
  int unsigned checks = 0;
  int unsigned errors = 0;

  meds_s1_timer dut (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .lite_req_i   (lite_req),
    .lite_rsp_o   (lite_rsp),
    .timer_irq_o  (timer_irq)
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
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    clocks(1);

    read_reg("reset control", 4'h0, 32'h0);
    read_reg("reset compare", 4'h4, 32'h0);
    read_reg("reset counter", 4'h8, 32'h0);
    read_reg("invalid address", 4'hc, 32'h0);

    write_reg(4'h4, 32'd0);
    read_reg("compare value", 4'h4, 32'd0);
    write_reg(4'h0, 32'h1);
    clocks(1);
    check1("periodic irq", timer_irq, 1'b1);
    write_reg(4'h0, 32'h5);
    check1("simultaneous action wins clear", timer_irq, 1'b1);
    write_reg(4'h0, 32'h0);
    clocks(1);
    write_reg(4'h0, 32'h4);
    check1("timer irq clear", timer_irq, 1'b0);

    write_reg(4'h4, 32'd2);
    write_reg(4'h0, 32'h3);
    clocks(4);
    check1("one-shot irq", timer_irq, 1'b1);
    read_reg("one-shot disables", 4'h0, 32'h6);

    write_reg(4'h0, 32'h4);
    write_reg(4'h4, 32'h0);
    write_reg(4'h0, 32'h1);
    clocks(1);
    check1("compare zero irq", timer_irq, 1'b1);
    read_reg("counter is readable", 4'h8, dut.cnt_q);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_timer failed");
    end
  end

endmodule
