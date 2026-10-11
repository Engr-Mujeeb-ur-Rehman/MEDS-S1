// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
`timescale 1ns / 1ps

module meds_s1_timer #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4 // 4 bytes covering offsets 0x0, 0x4, 0x8
)(
    // Global Clock & Reset
    input  logic                   clk_i,
    input  logic                   rst_ni,         // Active-low asynchronous reset

    // AXI4-Lite Write Channels
    input  logic [ADDR_WIDTH-1:2]  s_axi_awaddr_i,
    input  logic                   s_axi_awvalid_i,
    output logic                   s_axi_awready_o,
    input  logic [DATA_WIDTH-1:0]  s_axi_wdata_i,
    input  logic                   s_axi_wvalid_i,
    output logic                   s_axi_wready_o,
    output logic [1:0]             s_axi_bresp_o,
    output logic                   s_axi_bvalid_o,
    input  logic                   s_axi_bready_i,

    // AXI4-Lite Read Channels
    input  logic [ADDR_WIDTH-1:2]  s_axi_araddr_i,
    input  logic                   s_axi_arvalid_i,
    output logic                   s_axi_arready_o,
    output logic [DATA_WIDTH-1:0]  s_axi_rdata_o,
    output logic [1:0]             s_axi_rresp_o,
    output logic                   s_axi_rvalid_o,
    input  logic                   s_axi_rready_i,

    // Interrupt Request Line to PLIC
    output logic                   timer_irq_o
);

    // 1. AXI4-Lite Handshake Logic
    
    logic aw_en;
    logic [1:0] axi_awaddr_reg;
    logic [1:0] axi_araddr_reg;

    assign s_axi_bresp_o = 2'b00; // OKAY
    assign s_axi_rresp_o = 2'b00; // OKAY

    // Write handshake
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_awready_o <= 1'b0;
            s_axi_wready_o  <= 1'b0;
            s_axi_bvalid_o  <= 1'b0;
            aw_en           <= 1'b1;
            axi_awaddr_reg  <= '0;
        end else begin
            if (~s_axi_awready_o && s_axi_awvalid_i && s_axi_wvalid_i && aw_en) begin
                s_axi_awready_o <= 1'b1;
                s_axi_wready_o  <= 1'b1;
                axi_awaddr_reg  <= s_axi_awaddr_i;
                aw_en          <= 1'b0;
            end else begin
                s_axi_awready_o <= 1'b0;
                s_axi_wready_o  <= 1'b0;
            end

            if (s_axi_awready_o && s_axi_wready_o) begin
                s_axi_bvalid_o <= 1'b1;
            end else if (s_axi_bready_i && s_axi_bvalid_o) begin
                s_axi_bvalid_o <= 1'b0;
                aw_en        <= 1'b1;
            end
        end
    end

    
    // 2. Isolated Timer Address Decoder
    
    logic [1:0] dec_addr = (s_axi_awready_o && s_axi_wready_o) ? axi_awaddr_reg : s_axi_awaddr_i;
    logic       write_en = (s_axi_awready_o && s_axi_wready_o) || (s_axi_awvalid_i && s_axi_wvalid_i);

    // Offset 0x0: Control Register (Bit 0: EN, Bit 1: MODE, Bit 2: SW_CLR)
    logic we_ctrl = (~dec_addr[1]) & (~dec_addr[0]) & write_en; 
    
    // Offset 0x4: Compare Register
    logic we_com  = (~dec_addr[1]) & (dec_addr[0]) & write_en; 

    // Extracting clear signal directly from AXI write data payload
    logic sw_clr_timer = we_ctrl & s_axi_wdata_i[2];

    
    // 3. Timer Control & Compare Registers
   
    logic                    timer_en_q;
    logic                    timer_mode_q;
    logic [DATA_WIDTH-1:0]   timer_com_q;
    logic                    oneshot_halt_pulse;

    // Timer Enable & Mode Register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_en_q   <= 1'b0;
            timer_mode_q <= 1'b0;
        end else if (oneshot_halt_pulse) begin
            timer_en_q   <= 1'b0; // Hardware auto-shutdown for One-Shot
        end else if (we_ctrl) begin
            timer_en_q   <= s_axi_wdata_i[0];
            timer_mode_q <= s_axi_wdata_i[1];
        end
    end

    // Timer Compare Register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_com_q <= '0;
        end else if (we_com) begin
            timer_com_q <= s_axi_wdata_i;
        end
    end

   
    // 4. Timer Datapath: Counter, Subtractor, Logic & Routing
    
    logic [DATA_WIDTH-1:0] cnt_q;
    logic [DATA_WIDTH-1:0] adder_out = cnt_q + 1'b1;

    // N-bit Subtractor (CNT_Q - CMP_Q) 
    // Appending 1'b0 to prevent overflow and isolate the true borrow bit
    logic [DATA_WIDTH:0] sub_result = {1'b0, cnt_q} - {1'b0, timer_com_q};
    
    // The NOT gate connected to the borrow-out pin
    logic borrow_out = sub_result[DATA_WIDTH];
    logic match_signal = ~borrow_out; // Creates (CNT_Q >= COM_Q)

    // Safety Interlock Gate (AND MATCH.EN)
    logic action_pulse = match_signal & timer_en_q;

    // Mode Routing (Demux/Masking Logic)
    logic periodic_reset_pulse = (~timer_mode_q) & action_pulse;
    assign oneshot_halt_pulse = (timer_mode_q)  & action_pulse;

    // Cascaded MUXes for the Counter
    // MUX 1: Hold (0) / Count (1)
    logic [DATA_WIDTH-1:0] mux1_out = (timer_en_q) ? adder_out : cnt_q;
    
    // MUX 2: Pass Data (0) / Force Zero (1)
    logic [DATA_WIDTH-1:0] mux2_out = (periodic_reset_pulse) ? '0 : mux1_out;

    // The N-bit Counter Register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_q <= '0; // External System Reset
        end else begin
            cnt_q <= mux2_out;
        end
    end

   
    // 5. Timer IRQ RS Latch
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            timer_irq_o <= 1'b0;
        end else if (action_pulse) begin
            timer_irq_o <= 1'b1; // Set (S)
        end else if (sw_clr_timer) begin
            timer_irq_o <= 1'b0; // Reset (R)
        end
    end

    
    // 6. AXI4-Lite Read Channel
   
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_arready_o <= 1'b0;
            s_axi_rvalid_o  <= 1'b0;
            s_axi_rdata_o   <= '0;
            axi_araddr_reg<= '0;
        end else begin
            if (~s_axi_arready_o && s_axi_arvalid_i) begin
                s_axi_arready_o <= 1'b1;
                axi_araddr_reg  <= s_axi_araddr_i;
            end else begin
                s_axi_arready_o <= 1'b0;
            end

            if (s_axi_arready_o && s_axi_arvalid_i && ~s_axi_rvalid_o) begin
                s_axi_rvalid_o <= 1'b1;
                case (axi_araddr_reg)
                    2'b00: s_axi_rdata_o <= {29'b0, timer_irq_o, timer_mode_q, timer_en_q};
                    2'b01: s_axi_rdata_o <= timer_com_q;
                    2'b10: s_axi_rdata_o <= cnt_q; // Exposing current count for software polling
                    default: s_axi_rdata_o <= '0;
                endcase
            end else if (s_axi_rvalid_o && s_axi_rready_i) begin
                s_axi_rvalid_o <= 1'b0;
            end
        end
    end

endmodule
