// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_lite_pkg : the I4 peripheral-bus contract                 [COMPLETE]
//
// Every peripheral on the MEDS-S1 AXI4-Lite subtree -- CLINT, PLIC, UART, SPI,
// GPIO, timers, and every accelerator MMIO window -- presents exactly the two
// struct ports declared here and nothing else:
//
//     input  lite_req_t lite_req_i,
//     output lite_rsp_t lite_rsp_o
//
// NOT a port per AXI channel.  A peripheral with 20 loose AXI signals in its
// port list cannot be connected to the crossbar by the generator (R-04), cannot
// be swapped for another implementation, and grows a new port every time the
// bus gains a signal.  One struct in, one struct out: the port list never
// changes again.
//
// Field names match pulp-platform/axi's lite typedefs, so when T-04 brings up
// axi_lite_xbar these connect with no adapter.
//
// Reference: INTERFACES.md section 3 (I4), SPEC section 24, ADR-0005.
// Change policy: INTERFACES.md section 10.  This is an architect-owned file.
// =============================================================================

package meds_s1_lite_pkg;

  // ---------------------------------------------------------------------------
  // Bus geometry
  //
  // DW is 64, not 32.  mtime and mtimecmp are architecturally 64-bit registers
  // and stock OpenSBI issues a single 8-byte access to them on RV64; a 32-bit
  // bus forces every BSP author to hand-write the read-high/read-low/re-read
  // sequence, and the failure when they get it wrong appears once per 2^32
  // ticks.  The cost is 32 wires on a subtree that carries no traffic.
  // 32-bit peripherals are unaffected -- meds_s1_lite_regif gives them a 32-bit
  // register view and handles the byte lane.  See ADR-0005.
  // ---------------------------------------------------------------------------
  parameter int unsigned LITE_AW = 40;            // INTERFACES.md section 3
  parameter int unsigned LITE_DW = 64;
  parameter int unsigned LITE_SW = LITE_DW / 8;

  typedef logic [LITE_AW-1:0] lite_addr_t;
  typedef logic [LITE_DW-1:0] lite_data_t;
  typedef logic [LITE_SW-1:0] lite_strb_t;
  typedef logic [1:0]         lite_resp_t;

  // AXI4-Lite response encoding.  EXOKAY does not exist on Lite -- there are no
  // exclusive accesses to have.
  parameter lite_resp_t RESP_OKAY   = 2'b00;
  parameter lite_resp_t RESP_SLVERR = 2'b10;
  parameter lite_resp_t RESP_DECERR = 2'b11;

  // ---------------------------------------------------------------------------
  // Channel payloads
  //
  // AXI4-Lite drops id, len, size, burst, lock, cache, region and qos.  Only
  // prot survives, and only because the privilege check needs it later.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    lite_addr_t addr;
    logic [2:0] prot;
  } lite_ax_chan_t;

  typedef struct packed {
    lite_data_t data;
    lite_strb_t strb;
  } lite_w_chan_t;

  typedef struct packed {
    lite_resp_t resp;
  } lite_b_chan_t;

  typedef struct packed {
    lite_data_t data;
    lite_resp_t resp;
  } lite_r_chan_t;

  // ---------------------------------------------------------------------------
  // The two bundles.  Master-driven signals in req, slave-driven in rsp.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    lite_ax_chan_t aw;
    logic          aw_valid;
    lite_w_chan_t  w;
    logic          w_valid;
    logic          b_ready;
    lite_ax_chan_t ar;
    logic          ar_valid;
    logic          r_ready;
  } lite_req_t;

  typedef struct packed {
    logic         aw_ready;
    logic         w_ready;
    logic         ar_ready;
    lite_b_chan_t b;
    logic         b_valid;
    lite_r_chan_t r;
    logic         r_valid;
  } lite_rsp_t;

  // Safe idle values.  A peripheral held in reset drives this, never 'x.
  parameter lite_rsp_t LITE_RSP_IDLE = '{
    aw_ready: 1'b0, w_ready: 1'b0, ar_ready: 1'b0,
    b: '{resp: RESP_OKAY}, b_valid: 1'b0,
    r: '{data: '0, resp: RESP_OKAY}, r_valid: 1'b0
  };

endpackage
