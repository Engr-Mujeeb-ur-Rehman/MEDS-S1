# `meds_s1_lite_axi_adapter`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | _(assign)_ |
| **Backup** | _(assign)_ |
| **Project** | M-03 |
| **Spec** | `specs/INTERFACES.md` I4 |
| **Source** | `rtl/common/meds_s1_lite_axi_adapter.sv` |
| **Testbench** | TODO — no dedicated testbench yet |

## Purpose

This module is the single AXI4-Lite boundary for peripherals that implement the
shared MEDS-S1 Lite request/response structures. It owns AXI channel handshakes
and translates one accepted AXI request into a `lite_req_t` transaction.

## Interface contract

The adapter accepts a write when AXI address and data valid are asserted
together, and accepts a read when no write is pending and the read address is
valid. It presents the accepted request through `lite_req_o` and waits for a
valid, ready Lite response before producing the AXI response. Peripheral
modules must not implement AXI ports or AXI handshake state themselves.

| Interface | Meaning | Contract |
|---|---|---|
| AXI4-Lite ports | External bus | 32-bit data and 4-bit byte address window |
| `lite_req_o` | Shared peripheral request | valid request with byte address, write data, and strobes |
| `lite_rsp_i` | Shared peripheral response | ready acknowledges the request; valid carries read data or error |

**Handshake:** AXI address and data are accepted together for writes. One
request is held until its Lite response is accepted.
**Latency:** read data is returned after the Lite response handshake.
**Backpressure:** AXI write and read responses remain valid until the master
asserts the corresponding ready signal.
**Reset state:** outstanding write/read response state and read data clear to
zero.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `LITE_DATA_WIDTH` | 32 | shared package constant | AXI and Lite data width |
| `LITE_ADDR_WIDTH` | 4 | shared package constant | full byte address width |
| `LITE_STRB_WIDTH` | 4 | derived package constant | write-strobe width |

## Behaviour

The adapter serializes one read or write request at a time. It maps AXI write
strobes to `lite_req_t.wstrb`, maps AXI byte addresses into the shared request,
and maps the Lite error bit to an AXI SLVERR response. Peripheral-specific
register decoding and state remain outside this module.

## Exceptions and errors

The adapter reports `lite_rsp_i.err` as AXI SLVERR. It does not generate errors
for address-map misses; each peripheral defines its own unmapped-register
response.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | TODO | no dedicated testbench yet |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

AXI address and data channels are intentionally accepted together, matching the
current peripheral contract. The adapter serializes requests rather than
supporting multiple outstanding transactions.

## Open questions

- Add a focused adapter testbench covering response backpressure and error mapping.