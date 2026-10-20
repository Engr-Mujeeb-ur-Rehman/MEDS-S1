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

    localparam logic [3:0] GPIO_DIR_OFFSET  = 4'h0;
    localparam logic [3:0] GPIO_DATA_OFFSET = 4'h4;
    localparam logic [3:0] GPIO_IRQ_OFFSET  = 4'h8;

    logic [7:0] gpio_dir_q;
    logic [7:0] gpio_dout_q;
    logic [7:0] pin_input_val;
    logic [7:0] syn1_q;
    logic [7:0] syn2_q;
    logic [7:0] delay_q;
    logic [7:0] gpio_edge_pulse;

    // Write channel capture
    logic       aw_captured_q;
    logic       w_captured_q;
    /* verilator lint_off UNUSEDSIGNAL */
    lite_addr_t aw_addr_q;
    lite_data_t w_data_q;
    lite_strb_t w_strb_q;
    /* verilator lint_on UNUSEDSIGNAL */
    logic       b_valid_q;

    // Read channel capture
    logic       r_valid_q;
    logic [31:0] read_word_q;

    wire aw_active = (lite_req_i.aw_valid && lite_rsp_o.aw_ready) || aw_captured_q;
    wire w_active  = (lite_req_i.w_valid && lite_rsp_o.w_ready) || w_captured_q;

    wire [3:0]  write_offset = aw_captured_q ? aw_addr_q[3:0] : lite_req_i.aw.addr[3:0];
    wire        is_upper     = write_offset[2];

    wire [7:0]  write_byte   = is_upper
                             ? (w_captured_q ? w_data_q[39:32] : lite_req_i.w.data[39:32])
                             : (w_captured_q ? w_data_q[7:0]   : lite_req_i.w.data[7:0]);
    wire        write_strb0  = is_upper
                             ? (w_captured_q ? w_strb_q[4] : lite_req_i.w.strb[4])
                             : (w_captured_q ? w_strb_q[0] : lite_req_i.w.strb[0]);

    wire write_fire = aw_active && w_active && (!b_valid_q || lite_req_i.b_ready);

    wire we_dir   = write_fire && write_strb0 && (write_offset == GPIO_DIR_OFFSET);
    wire we_dout  = write_fire && write_strb0 && (write_offset == GPIO_DATA_OFFSET);
    wire [7:0] irq_clear = (write_fire && write_strb0 && (write_offset == GPIO_IRQ_OFFSET))
                           ? write_byte : 8'h0;

    // AXI write channels
    assign lite_rsp_o.aw_ready = !aw_captured_q && (!b_valid_q || lite_req_i.b_ready);
    assign lite_rsp_o.w_ready  = !w_captured_q  && (!b_valid_q || lite_req_i.b_ready);
    assign lite_rsp_o.b.resp   = RESP_OKAY;
    assign lite_rsp_o.b_valid  = b_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_captured_q <= 1'b0;
            w_captured_q  <= 1'b0;
            aw_addr_q     <= '0;
            w_data_q      <= '0;
            w_strb_q      <= '0;
            b_valid_q     <= 1'b0;
        end else begin
            if (lite_rsp_o.aw_ready && lite_req_i.aw_valid) begin
                aw_captured_q <= 1'b1;
                aw_addr_q     <= lite_req_i.aw.addr;
            end
            if (lite_rsp_o.w_ready && lite_req_i.w_valid) begin
                w_captured_q <= 1'b1;
                w_data_q     <= lite_req_i.w.data;
                w_strb_q     <= lite_req_i.w.strb;
            end

            if (write_fire) begin
                aw_captured_q <= 1'b0;
                w_captured_q  <= 1'b0;
                b_valid_q     <= 1'b1;
            end else if (b_valid_q && lite_req_i.b_ready) begin
                b_valid_q     <= 1'b0;
            end
        end
    end

    // Read channel logic
    assign lite_rsp_o.ar_ready = !r_valid_q || lite_req_i.r_ready;
    assign lite_rsp_o.r.resp   = RESP_OKAY;
    assign lite_rsp_o.r.data   = {read_word_q, read_word_q};
    assign lite_rsp_o.r_valid  = r_valid_q;

    logic [31:0] read_data_comb;
    wire [3:0] read_offset = lite_req_i.ar.addr[3:0];

    always_comb begin
        read_data_comb = '0;
        case (read_offset)
            GPIO_DIR_OFFSET:  read_data_comb = {24'b0, gpio_dir_q};
            GPIO_DATA_OFFSET: read_data_comb = {24'b0, syn2_q};
            GPIO_IRQ_OFFSET:  read_data_comb = {24'b0, gpio_irq_o};
            default:          read_data_comb = '0;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_valid_q   <= 1'b0;
            read_word_q <= '0;
        end else begin
            if (lite_rsp_o.ar_ready && lite_req_i.ar_valid) begin
                r_valid_q   <= 1'b1;
                read_word_q <= read_data_comb;
            end else if (r_valid_q && lite_req_i.r_ready) begin
                r_valid_q   <= 1'b0;
            end
        end
    end

    // GPIO registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dir_q <= 8'h0;
        end else if (we_dir) begin
            gpio_dir_q <= write_byte;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dout_q <= 8'h0;
        end else if (we_dout) begin
            gpio_dout_q <= write_byte;
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
            syn1_q  <= 8'h0;
            syn2_q  <= 8'h0;
            delay_q <= 8'h0;
        end else begin
            syn1_q  <= pin_input_val;
            syn2_q  <= syn1_q;
            delay_q <= syn2_q;
        end
    end

    assign gpio_edge_pulse = syn2_q ^ delay_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_irq_o <= 8'h0;
        end else begin
            gpio_irq_o <= (gpio_irq_o & ~irq_clear) | gpio_edge_pulse;
        end
    end

endmodule

