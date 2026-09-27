`timescale 1ns / 1ps

module meds_s1_timer #(
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

    // Interrupt Request Line to PLIC
    output logic                   timer_irq
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

    
    // 2. Isolated Timer Address Decoder
    
    wire [1:0] dec_addr = (s_axi_awready && s_axi_wready) ? axi_awaddr_reg[3:2] : s_axi_awaddr[3:2];
    wire       write_en = (s_axi_awready && s_axi_wready) || (s_axi_awvalid && s_axi_wvalid);

    // Offset 0x0: Control Register (Bit 0: EN, Bit 1: MODE, Bit 2: SW_CLR)
    wire we_ctrl = (~dec_addr[1]) & (~dec_addr[0]) & write_en; 
    
    // Offset 0x4: Compare Register
    wire we_com  = (~dec_addr[1]) & (dec_addr[0]) & write_en; 

    // Extracting clear signal directly from AXI write data payload
    wire sw_clr_timer = we_ctrl & s_axi_wdata[2];

    
    // 3. Timer Control & Compare Registers
   
    logic                    timer_en_q;
    logic                    timer_mode_q;
    logic [DATA_WIDTH-1:0]   timer_com_q;
    logic                    oneshot_halt_pulse;

    // Timer Enable & Mode Register
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            timer_en_q   <= 1'b0;
            timer_mode_q <= 1'b0;
        end else if (oneshot_halt_pulse) begin
            timer_en_q   <= 1'b0; // Hardware auto-shutdown for One-Shot
        end else if (we_ctrl) begin
            timer_en_q   <= s_axi_wdata[0];
            timer_mode_q <= s_axi_wdata[1];
        end
    end

    // Timer Compare Register
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            timer_com_q <= '0;
        end else if (we_com) begin
            timer_com_q <= s_axi_wdata;
        end
    end

   
    // 4. Timer Datapath: Counter, Subtractor, Logic & Routing
    
    logic [DATA_WIDTH-1:0] cnt_q;
    wire  [DATA_WIDTH-1:0] adder_out = cnt_q + 1'b1;

    // N-bit Subtractor (CNT_Q - CMP_Q) 
    // Appending 1'b0 to prevent overflow and isolate the true borrow bit
    wire [DATA_WIDTH:0] sub_result = {1'b0, cnt_q} - {1'b0, timer_com_q};
    
    // The NOT gate connected to the borrow-out pin
    wire borrow_out = sub_result[DATA_WIDTH];
    wire match_signal = ~borrow_out; // Creates (CNT_Q >= COM_Q)

    // Safety Interlock Gate (AND MATCH.EN)
    wire action_pulse = match_signal & timer_en_q;

    // Mode Routing (Demux/Masking Logic)
    wire periodic_reset_pulse = (~timer_mode_q) & action_pulse;
    assign oneshot_halt_pulse = (timer_mode_q)  & action_pulse;

    // Cascaded MUXes for the Counter
    // MUX 1: Hold (0) / Count (1)
    wire [DATA_WIDTH-1:0] mux1_out = (timer_en_q) ? adder_out : cnt_q;
    
    // MUX 2: Pass Data (0) / Force Zero (1)
    wire [DATA_WIDTH-1:0] mux2_out = (periodic_reset_pulse) ? '0 : mux1_out;

    // The N-bit Counter Register
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cnt_q <= '0; // External System Reset
        end else begin
            cnt_q <= mux2_out;
        end
    end

   
    // 5. Timer IRQ RS Latch
    
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            timer_irq <= 1'b0;
        end else if (action_pulse) begin
            timer_irq <= 1'b1; // Set (S)
        end else if (sw_clr_timer) begin
            timer_irq <= 1'b0; // Reset (R)
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
                    2'b00: s_axi_rdata <= {29'b0, timer_irq, timer_mode_q, timer_en_q};
                    2'b01: s_axi_rdata <= timer_com_q;
                    2'b10: s_axi_rdata <= cnt_q; // Exposing current count for software polling
                    default: s_axi_rdata <= '0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule