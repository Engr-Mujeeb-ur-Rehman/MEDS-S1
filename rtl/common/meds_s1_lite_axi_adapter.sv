// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//



module meds_s1_lite_axi_adapter
  import meds_s1_lite_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic [LITE_ADDR_WIDTH-1:0] s_axi_awaddr_i,
    input  logic                   s_axi_awvalid_i,
    output logic                   s_axi_awready_o,
    input  logic [LITE_DATA_WIDTH-1:0] s_axi_wdata_i,
    input  logic [LITE_STRB_WIDTH-1:0] s_axi_wstrb_i,
    input  logic                   s_axi_wvalid_i,
    output logic                   s_axi_wready_o,
    output logic [1:0]             s_axi_bresp_o,
    output logic                   s_axi_bvalid_o,
    input  logic                   s_axi_bready_i,

    input  logic [LITE_ADDR_WIDTH-1:0] s_axi_araddr_i,
    input  logic                   s_axi_arvalid_i,
    output logic                   s_axi_arready_o,
    output logic [LITE_DATA_WIDTH-1:0] s_axi_rdata_o,
    output logic [1:0]             s_axi_rresp_o,
    output logic                   s_axi_rvalid_o,
    input  logic                   s_axi_rready_i,

    output meds_s1_lite_pkg::lite_req_t lite_req_o,
    input  meds_s1_lite_pkg::lite_rsp_t lite_rsp_i
);

  logic read_busy_q;
  logic write_busy_q;

  logic write_accept;
  logic read_accept;

  always_comb begin
    lite_req_o = '0;
    lite_req_o.valid = write_accept || read_accept;
    lite_req_o.write = write_accept;
    lite_req_o.addr = write_accept ? s_axi_awaddr_i : s_axi_araddr_i;
    lite_req_o.wdata = s_axi_wdata_i;
    lite_req_o.wstrb = s_axi_wstrb_i;
    lite_req_o.rsp_ready = 1'b1;
  end

  always_comb begin
    write_accept = !write_busy_q && !read_busy_q &&
                   s_axi_awvalid_i && s_axi_wvalid_i;
    read_accept = !write_busy_q && !read_busy_q &&
                  !write_accept && s_axi_arvalid_i;

    s_axi_awready_o = write_accept;
    s_axi_wready_o  = write_accept;
    s_axi_arready_o = read_accept;
    s_axi_bresp_o   = lite_rsp_i.err ? 2'b10 : 2'b00;
    s_axi_rresp_o   = lite_rsp_i.err ? 2'b10 : 2'b00;
  end

  assign s_axi_bvalid_o = write_busy_q;
  assign s_axi_rvalid_o = read_busy_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      write_busy_q <= 1'b0;
      read_busy_q  <= 1'b0;
      s_axi_rdata_o <= '0;
    end else begin
      if (write_busy_q && s_axi_bready_i) begin
        write_busy_q <= 1'b0;
      end
      if (read_busy_q && s_axi_rready_i) begin
        read_busy_q <= 1'b0;
      end

      if (lite_rsp_i.valid && lite_rsp_i.ready && write_accept) begin
        write_busy_q <= 1'b1;
      end
      if (lite_rsp_i.valid && lite_rsp_i.ready && read_accept) begin
        read_busy_q   <= 1'b1;
        s_axi_rdata_o <= lite_rsp_i.rdata;
      end
    end
  end

endmodule
