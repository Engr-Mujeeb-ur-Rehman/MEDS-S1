`timescale 1ns / 1ps

module meds_s1_gpio #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4 // 4 bytes covering offsets 0x0, 0x4, 0x8
)(
    // Global Clock & Reset
    input  logic                   sys_clk,
    input  logic                   sys_rst_n,      // Active-low asynchronous reset

    // AXI4-Lite Write Channels
    input  logic [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,
    input  logic [DATA_WIDTH-1:0]  s_axi_wdata,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,
    output logic [1:0]             s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    // AXI4-Lite Read Channels
    input  logic [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,
    output logic [DATA_WIDTH-1:0]  s_axi_rdata,
    output logic [1:0]             s_axi_rresp,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,

    // External GPIO Physical Interface
    inout  wire                    gpio_pin,

    // Interrupt Request Line to PLIC
    output logic                   gpio_irq
);

    // 1. AXI4-Lite Handshake Logic
  
    logic aw_en;
    logic [ADDR_WIDTH-1:0] axi_awaddr_reg;
    logic [ADDR_WIDTH-1:0] axi_araddr_reg;

    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_rresp = 2'b00; // OKAY

    // Write handshake
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            aw_en           <= 1'b1;
            axi_awaddr_reg  <= '0;
        end else begin
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
                s_axi_awready  <= 1'b1;
                s_axi_wready   <= 1'b1;
                axi_awaddr_reg <= s_axi_awaddr;
                aw_en          <= 1'b0;
            end else begin
                s_axi_awready  <= 1'b0;
                s_axi_wready   <= 1'b0;
            end

            if (s_axi_awready && s_axi_wready) begin
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
                aw_en        <= 1'b1;
            end
        end
    end

    
    // 2. Address Decoder (Isolated for GPIO)
    
    wire [1:0] dec_addr = (s_axi_awready && s_axi_wready) ? axi_awaddr_reg[3:2] : s_axi_awaddr[3:2];
    wire       write_en = (s_axi_awready && s_axi_wready) || (s_axi_awvalid && s_axi_wvalid);

    // Decoding offsets matching the cascaded AND/NOT logic
    wire we_dir = (~dec_addr[1]) & (~dec_addr[0]) & write_en; // Offset 0x0
    wire we_dout = (~dec_addr[1]) & (dec_addr[0]) & write_en; // Offset 0x4
    wire sw_clr  = (dec_addr[1]) & (~dec_addr[0]) & write_en & s_axi_wdata[0]; // Offset 0x8 for IRQ clear

    
    // 3. GPIO Register Datapath (with Feedback MUX logic)
    
    logic gpio_dir_q;
    logic gpio_dout_q;

    // GPIO DIR Register
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            gpio_dir_q <= 1'b0;
        end else if (we_dir) begin
            gpio_dir_q <= s_axi_wdata[0];
        end
    end

    // GPIO DOUT Register
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            gpio_dout_q <= 1'b0;
        end else if (we_dout) begin
            gpio_dout_q <= s_axi_wdata[0];
        end
    end

    
    // 4. Physical Pin & Tri-State Buffer
    
    // Translates to: TRI STATE BUF (EN=DIR_Q)
    assign gpio_pin = (gpio_dir_q) ? gpio_dout_q : 1'bz; 
    wire pin_input_val = gpio_pin;

    
    // 5. Input Synchronizer & Edge Detector Subsystem
    
    logic syn1_q;
    logic syn2_q;
    logic delay_q;

    // Converts multi-cycle pin states into a 1-cycle IRQ pulse
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
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
    wire gpio_edge_pulse = syn2_q ^ delay_q;

    // GPIO PENDING RS Latch (S=EDGE, R=SW clr)
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            gpio_irq <= 1'b0;
        end else if (gpio_edge_pulse) begin
            gpio_irq <= 1'b1;  // Set (S)
        end else if (sw_clr) begin
            gpio_irq <= 1'b0;  // Reset (R)
        end
    end

    
    // 6. AXI4-Lite Read Channel
    
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            axi_araddr_reg<= '0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready  <= 1'b1;
                axi_araddr_reg <= s_axi_araddr;
            end else begin
                s_axi_arready  <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                case (axi_araddr_reg[3:2])
                    2'b00: s_axi_rdata <= {31'b0, gpio_dir_q};
                    2'b01: s_axi_rdata <= {31'b0, syn2_q}; // Bypass delay to read live synchronized state
                    2'b10: s_axi_rdata <= {31'b0, gpio_irq}; // Read IRQ status
                    default: s_axi_rdata <= '0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule