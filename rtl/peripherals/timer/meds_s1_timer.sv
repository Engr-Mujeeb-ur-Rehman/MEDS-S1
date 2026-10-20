// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//

module meds_s1_timer
  import meds_s1_lite_pkg::*;
(
    input  logic       clk_i,
    input  logic       rst_ni,
    input  lite_req_t  lite_req_i,
    output lite_rsp_t  lite_rsp_o,
    output logic       timer_irq_o
);

    localparam logic [3:0] TIMER_CTRL_OFFSET    = 4'h0;
    localparam logic [3:0] TIMER_COMPARE_OFFSET = 4'h4;
    localparam logic [3:0] TIMER_COUNT_OFFSET   = 4'h8;

    logic                    timer_en_q;
    logic                    timer_mode_q;
    logic [31:0]             timer_com_q;
    logic                    oneshot_halt_pulse;
    logic [31:0]             cnt_q;
    logic [31:0]             adder_out;
    logic                    borrow_out;
    logic                    match_signal;
    logic                    action_pulse;
    logic                    periodic_reset_pulse;
    logic [31:0]             mux1_out;
    logic [31:0]             mux2_out;

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

    wire [31:0] write_word   = is_upper
                             ? (w_captured_q ? w_data_q[63:32] : lite_req_i.w.data[63:32])
                             : (w_captured_q ? w_data_q[31:0]  : lite_req_i.w.data[31:0]);
    wire        write_strb0  = is_upper
                             ? (w_captured_q ? w_strb_q[4] : lite_req_i.w.strb[4])
                             : (w_captured_q ? w_strb_q[0] : lite_req_i.w.strb[0]);

    wire write_fire = aw_active && w_active && (!b_valid_q || lite_req_i.b_ready);

    wire we_ctrl = write_fire && write_strb0 && (write_offset == TIMER_CTRL_OFFSET);
    wire we_com  = write_fire && (write_offset == TIMER_COMPARE_OFFSET);
    wire timer_irq_clear = we_ctrl && write_word[2];

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
            TIMER_CTRL_OFFSET:    read_data_comb = {29'b0, timer_irq_o, timer_mode_q, timer_en_q};
            TIMER_COMPARE_OFFSET: read_data_comb = timer_com_q;
            TIMER_COUNT_OFFSET:   read_data_comb = cnt_q;
            default:              read_data_comb = '0;
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

    // Timer control registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_en_q   <= 1'b0;
            timer_mode_q <= 1'b0;
        end else if (oneshot_halt_pulse) begin
            timer_en_q <= 1'b0;
        end else if (we_ctrl) begin
            timer_en_q   <= write_word[0];
            timer_mode_q <= write_word[1];
        end
    end

    // Timer compare register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_com_q <= '0;
        end else if (we_com) begin
            timer_com_q <= write_word;
        end
    end

    // Counter datapath
    assign adder_out = cnt_q + 1'b1;
    assign borrow_out = (cnt_q < timer_com_q);
    assign match_signal = ~borrow_out;
    assign action_pulse = match_signal & timer_en_q;
    assign periodic_reset_pulse = (~timer_mode_q) & action_pulse;
    assign oneshot_halt_pulse = timer_mode_q & action_pulse;
    assign mux1_out = timer_en_q ? adder_out : cnt_q;
    assign mux2_out = periodic_reset_pulse ? '0 : mux1_out;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_q <= '0;
        end else begin
            cnt_q <= mux2_out;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_irq_o <= 1'b0;
        end else if (action_pulse) begin
            timer_irq_o <= 1'b1;
        end else if (timer_irq_clear) begin
            timer_irq_o <= 1'b0;
        end
    end

endmodule

