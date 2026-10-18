// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//

module meds_s1_gpio
  import meds_s1_lite_pkg::*;
(
    input  logic       clk_i,
    input  logic       rst_ni,
    input  lite_req_t  lite_req_i,
    output lite_rsp_t  lite_rsp_o,
    inout  logic [7:0] gpio_pin_io,
    output logic [7:0] gpio_irq_o
);

    localparam logic [LITE_ADDR_WIDTH-1:0] GPIO_DIR_OFFSET = 'h0;
    localparam logic [LITE_ADDR_WIDTH-1:0] GPIO_DATA_OFFSET = 'h4;
    localparam logic [LITE_ADDR_WIDTH-1:0] GPIO_IRQ_OFFSET = 'h8;

    logic write_fire;
    logic we_dir;
    logic we_dout;
    logic [7:0] irq_clear;
    logic [LITE_DATA_WIDTH-1:0] read_data;
    logic [7:0] gpio_dir_q;
    logic [7:0] gpio_dout_q;
    logic [7:0] pin_input_val;
    logic [7:0] syn1_q;
    logic [7:0] syn2_q;
    logic [7:0] delay_q;
    logic [7:0] gpio_edge_pulse;

    assign write_fire = lite_req_i.valid && lite_req_i.write &&
                        lite_req_i.rsp_ready && lite_rsp_o.ready;
    assign we_dir = write_fire && lite_req_i.wstrb[0] &&
                    (lite_req_i.addr == GPIO_DIR_OFFSET);
    assign we_dout = write_fire && lite_req_i.wstrb[0] &&
                     (lite_req_i.addr == GPIO_DATA_OFFSET);
    assign irq_clear = (write_fire && lite_req_i.wstrb[0] &&
                        (lite_req_i.addr == GPIO_IRQ_OFFSET))
                       ? lite_req_i.wdata[7:0] : '0;

    always_comb begin
        read_data = '0;
        case (lite_req_i.addr)
            GPIO_DIR_OFFSET:  read_data[7:0] = gpio_dir_q;
            GPIO_DATA_OFFSET: read_data[7:0] = syn2_q;
            GPIO_IRQ_OFFSET:  read_data[7:0] = gpio_irq_o;
            default: read_data = '0;
        endcase

        lite_rsp_o = '0;
        lite_rsp_o.ready = 1'b1;
        lite_rsp_o.valid = lite_req_i.valid;
        lite_rsp_o.rdata = read_data;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dir_q <= '0;
        end else if (we_dir) begin
            gpio_dir_q <= lite_req_i.wdata[7:0];
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dout_q <= '0;
        end else if (we_dout) begin
            gpio_dout_q <= lite_req_i.wdata[7:0];
        end
    end

    assign pin_input_val = gpio_pin_io;

    genvar gpio_idx;
    generate
        for (gpio_idx = 0; gpio_idx < 8; gpio_idx++) begin : gen_gpio_pins
            assign gpio_pin_io[gpio_idx] = gpio_dir_q[gpio_idx]
                                         ? gpio_dout_q[gpio_idx] : 1'bz;
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            syn1_q  <= '0;
            syn2_q  <= '0;
            delay_q <= '0;
        end else begin
            syn1_q  <= pin_input_val;
            syn2_q  <= syn1_q;
            delay_q <= syn2_q;
        end
    end

    assign gpio_edge_pulse = syn2_q ^ delay_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_irq_o <= '0;
        end else begin
            gpio_irq_o <= (gpio_irq_o & ~irq_clear) | gpio_edge_pulse;
        end
    end

endmodule
