// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//



package meds_s1_lite_pkg;

  parameter int unsigned LITE_DATA_WIDTH = 32;
  parameter int unsigned LITE_ADDR_WIDTH = 4;
  parameter int unsigned LITE_STRB_WIDTH = LITE_DATA_WIDTH / 8;

  // A request remains valid until the peripheral accepts its response.
  typedef struct packed {
    logic                         valid;
    logic                         write;
    logic [LITE_ADDR_WIDTH-1:0]   addr;
    logic [LITE_DATA_WIDTH-1:0]   wdata;
    logic [LITE_STRB_WIDTH-1:0]   wstrb;
    logic                         rsp_ready;
  } lite_req_t;

  // ready acknowledges the request; valid carries its read or write response.
  typedef struct packed {
    logic                         ready;
    logic                         valid;
    logic [LITE_DATA_WIDTH-1:0]   rdata;
    logic                         err;
  } lite_rsp_t;

endpackage
