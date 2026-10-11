// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//

`timescale 1ns / 1ps

module meds_s1_gpio #(
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
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [DATA_WIDTH-1:0]  s_axi_wdata_i,
    /* verilator lint_on UNUSEDSIGNAL */
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

    // External GPIO Physical Interface
    inout  logic                   gpio_pin_io,

    // Interrupt Request Line to PLIC
    output logic                   gpio_irq_o
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

    
    // 2. Address Decoder (Isolated for GPIO)
    
    logic [1:0] dec_addr = (s_axi_awready_o && s_axi_wready_o) ? axi_awaddr_reg : s_axi_awaddr_i;
    logic       write_en = (s_axi_awready_o && s_axi_wready_o) || (s_axi_awvalid_i && s_axi_wvalid_i);

    // Decoding offsets matching the cascaded AND/NOT logic
    logic we_dir = (~dec_addr[1]) & (~dec_addr[0]) & write_en; // Offset 0x0
    logic we_dout = (~dec_addr[1]) & (dec_addr[0]) & write_en; // Offset 0x4
    logic sw_clr  = (dec_addr[1]) & (~dec_addr[0]) & write_en & s_axi_wdata_i[0]; // Offset 0x8 for IRQ clear

    
    // 3. GPIO Register Datapath (with Feedback MUX logic)
    
    logic gpio_dir_q;
    logic gpio_dout_q;

    // GPIO DIR Register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dir_q <= 1'b0;
        end else if (we_dir) begin
            gpio_dir_q <= s_axi_wdata_i[0];
        end
    end

    // GPIO DOUT Register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_dout_q <= 1'b0;
        end else if (we_dout) begin
            gpio_dout_q <= s_axi_wdata_i[0];
        end
    end

    
    // 4. Physical Pin & Tri-State Buffer
    
    // Translates to: TRI STATE BUF (EN=DIR_Q)
    assign gpio_pin_io = (gpio_dir_q) ? gpio_dout_q : 1'bz;
    logic pin_input_val = gpio_pin_io;

    
    // 5. Input Synchronizer & Edge Detector Subsystem
    
    logic syn1_q;
    logic syn2_q;
    logic delay_q;

    // Converts multi-cycle pin states into a 1-cycle IRQ pulse
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            syn1_q  <= 1'b0;
            syn2_q  <= 1'b0;
            delay_q <= 1'b0;
        end else begin
            syn1_q  <= pin_input_val;
            syn2_q  <= syn1_q;
            delay_q <= syn2_q;
        end
    end

    // XOR EDGE DETECT logic
    logic gpio_edge_pulse = syn2_q ^ delay_q;

    // GPIO PENDING RS Latch (S=EDGE, R=SW clr)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_irq_o <= 1'b0;
        end else if (gpio_edge_pulse) begin
            gpio_irq_o <= 1'b1;  // Set (S)
        end else if (sw_clr) begin
            gpio_irq_o <= 1'b0;  // Reset (R)
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
                    2'b00: s_axi_rdata_o <= {31'b0, gpio_dir_q};
                    2'b01: s_axi_rdata_o <= {31'b0, syn2_q}; // Bypass delay to read live synchronized state
                    2'b10: s_axi_rdata_o <= {31'b0, gpio_irq_o}; // Read IRQ status
                    default: s_axi_rdata_o <= '0;
                endcase
            end else if (s_axi_rvalid_o && s_axi_rready_i) begin
                s_axi_rvalid_o <= 1'b0;
            end
        end
    end

endmodule
