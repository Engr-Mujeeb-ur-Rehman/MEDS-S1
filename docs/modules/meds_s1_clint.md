# `meds_s1_clint`

| | |
|---|---|
| **Status** | SKELETON — ports frozen, the implementation is T-05 work |
| **Project** | T-05 (WP9) |
| **Spec** | SPEC §24, INTERFACES.md §6 (I7), ADR-0005 |
| **Source** | `rtl/peripherals/meds_s1_clint.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_clint.sv` — **you write this** |


## Purpose

Core-local interrupts: the software interrupt (`msip`) and the timer interrupt (`mtime` /
`mtimecmp`) that the privileged specification requires of every RISC-V hart.

MEDS-S1 is **single-hart**, so there is no hart index in this module or its register map — one
`msip` bit, one `mtimecmp`, one `mtime`. A multi-hart port changes the module and the map together.

Note that "CLINT" is **not** in the privileged specification. It is the SiFive de-facto layout, which
is what existing software expects; the standardised successor is ACLINT (MTIMER + MSWI). We
implement the SiFive layout. _(G0: read the ACLINT spec and record here, in two sentences, which one
this module follows and what would have to change to move.)_

## Register map

Window: 64 KiB at `0x0200_0000` (the `clint` region in `configs/*.yaml`). `REG_DW = 64`.

| Offset | Name | Access | Width | Reset | Meaning |
|---|---|---|---|---|---|
| `0x0000` | `msip` | RW | 32 | `0` | bit 0 raises the software interrupt; bits 31:1 read as zero |
| `0x4000` | `mtimecmp` | RW | 64 | _(G0: state it — this reset value decides whether a timer interrupt is pending out of reset)_ | timer comparand |
| `0xBFF8` | `mtime` | RW | 64 | `0` | free-running real-time counter |

Everything else in the window is unmapped and returns `SLVERR`.

**Access widths.** 4 and 8 bytes, both naturally aligned. The 64-bit peripheral bus (ADR-0005) means
`mtime` and `mtimecmp` move in a single access, so the read-high/read-low/re-read sequence a 32-bit
bus would force on software does not exist here.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert |
| `rtc_tick_i` | in | 1 | real-time tick | **one `clk_i` cycle wide**, at `rtc_hz`, generated in `board_top` (SPEC §25). `mtime` counts this, never `clk_i` |
| `lite_req_i` / `lite_rsp_o` | | `lite_req_t` / `lite_rsp_t` | I4 bus | frozen; see `meds_s1_lite_regif` |
| `msip_o` | out | 1 | → `mip.MSIP` | level |
| `mtip_o` | out | 1 | → `mip.MTIP` | level, and **not** edge-detected anywhere |

**Reset state:** both interrupt outputs low. _(G0: confirm this actually follows from your `mtimecmp`
reset value — if `mtimecmp` resets to 0 then `mtime >= mtimecmp` is true immediately.)_

## Parameters

None. Single-hart by platform decision; the window geometry (`ADDR_W`, `REG_DW`) is fixed by the
`clint` region in `configs/*.yaml` and is a localparam, not a knob.

## Behaviour

_(Complete at G5.)_ Cover at minimum: what happens when software writes `mtimecmp` while `mtip` is
already asserted; whether `mtime` continues counting during a bus access to it; and — the question
you will be asked first — whether `mtip` is `>=` or `==`, and what breaks with the other one.

## Verification status

_(Complete at G5. The G2 exit criteria are the minimum list.)_

| Layer | Status | Where |
|---|---|---|
| Lint | clean (skeleton) | `make lint` |
| Unit test | — | `verif/unit/tb_meds_s1_clint.sv` |
