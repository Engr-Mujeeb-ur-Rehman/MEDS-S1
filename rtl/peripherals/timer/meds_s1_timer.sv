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

    localparam logic [LITE_ADDR_WIDTH-1:0] TIMER_CTRL_OFFSET = 'h0;
    localparam logic [LITE_ADDR_WIDTH-1:0] TIMER_COMPARE_OFFSET = 'h4;
    localparam logic [LITE_ADDR_WIDTH-1:0] TIMER_COUNT_OFFSET = 'h8;

    logic write_fire;
    logic we_ctrl;
    logic we_com;
    logic timer_irq_clear;
    logic [LITE_DATA_WIDTH-1:0] read_data;
    logic                    timer_en_q;
    logic                    timer_mode_q;
    logic [LITE_DATA_WIDTH-1:0] timer_com_q;
    logic                    oneshot_halt_pulse;
    logic [LITE_DATA_WIDTH-1:0] cnt_q;
    logic [LITE_DATA_WIDTH-1:0] adder_out;
    logic [LITE_DATA_WIDTH:0]   sub_result;
    logic                        borrow_out;
    logic                        match_signal;
    logic                        action_pulse;
    logic                        periodic_reset_pulse;
    logic [LITE_DATA_WIDTH-1:0] mux1_out;
    logic [LITE_DATA_WIDTH-1:0] mux2_out;

    assign write_fire = lite_req_i.valid && lite_req_i.write &&
                        lite_req_i.rsp_ready && lite_rsp_o.ready;
    assign we_ctrl = write_fire && lite_req_i.wstrb[0] &&
                     (lite_req_i.addr == TIMER_CTRL_OFFSET);
    assign we_com = write_fire &&
                    (lite_req_i.addr == TIMER_COMPARE_OFFSET);
    assign timer_irq_clear = we_ctrl && lite_req_i.wdata[2];

    always_comb begin
        read_data = '0;
        case (lite_req_i.addr)
            TIMER_CTRL_OFFSET:    read_data = {29'b0, timer_irq_o, timer_mode_q, timer_en_q};
            TIMER_COMPARE_OFFSET: read_data = timer_com_q;
            TIMER_COUNT_OFFSET:   read_data = cnt_q;
            default: read_data = '0;
        endcase

        lite_rsp_o = '0;
        lite_rsp_o.ready = 1'b1;
        lite_rsp_o.valid = lite_req_i.valid;
        lite_rsp_o.rdata = read_data;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_en_q   <= 1'b0;
            timer_mode_q <= 1'b0;
        end else if (oneshot_halt_pulse) begin
            timer_en_q <= 1'b0;
        end else if (we_ctrl) begin
            timer_en_q   <= lite_req_i.wdata[0];
            timer_mode_q <= lite_req_i.wdata[1];
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_com_q <= '0;
        end else if (we_com) begin
            timer_com_q <= lite_req_i.wdata;
        end
    end

    assign adder_out = cnt_q + 1'b1;
    assign sub_result = {1'b0, cnt_q} - {1'b0, timer_com_q};
    assign borrow_out = sub_result[LITE_DATA_WIDTH];
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
