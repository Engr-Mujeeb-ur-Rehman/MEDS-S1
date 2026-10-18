# `meds_s1_plic`

| | |
|---|---|
| **Status** | SKELETON — ports frozen, the implementation is T-05 work |
| **Project** | T-05 (WP9) |
| **Spec** | RISC-V PLIC specification v1.0, SPEC §24, INTERFACES.md §6 (I7) |
| **Source** | `rtl/peripherals/meds_s1_plic.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_plic.sv` — **you write this** |

## Purpose

Multiplexes every peripheral and accelerator interrupt into the core's external-interrupt line,
with per-source priority, enables and threshold, and a claim/complete handshake that guarantees an
interrupt is serviced exactly once.

MEDS-S1 is single-hart and M-mode only, so there is **one target context** — no target index and no
`0x1000` context stride to walk.

## Register map

Window: 4 MiB at `0x0C00_0000` (the `plic` region in `configs/*.yaml`). `REG_DW = 32` — every PLIC
register is 32 bits; `meds_s1_lite_regif` absorbs the byte lane.

| Offset | Name | Access | Reset | Meaning |
|---|---|---|---|---|
| `0x000000 + 4·s` | `priority[s]` | RW | `0` | source `s`'s priority. **0 means "never interrupt"** |
| `0x001000 + 4·(s/32)` | `pending` | RO | `0` | one bit per source |
| `0x002000 + 0x80·t + 4·(s/32)` | `enable[t]` | RW | `0` | which sources target `t` accepts |
| `0x200000 + 0x1000·t` | `threshold[t]` | RW | _(G0)_ | target `t` ignores priorities **≤** this |
| `0x200000 + 0x1000·t + 4` | `claim[t]` | RO | `0` | read: highest-priority eligible source, and clear its pending bit |
| `0x200000 + 0x1000·t + 4` | `complete[t]` | WO | — | write: re-arm the named source |

**Source 0 does not exist.** The specification reserves ID 0 as "no interrupt", which is what makes
a claim of `0` mean "nothing to service". `irq_i[0]` is therefore never read and `pending[0]` is
hard-wired low — that is a deliberate, permanently waived lint warning, not an oversight.

**Interrupt ID allocation** (SPEC §24): `0` reserved · `1–15` platform peripherals · `16–31`
accelerator sockets · `32+` expansion. IDs come from `soc.yaml` and are never hand-assigned twice.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` / `rst_ni` | in | 1 | clock, reset | async assert, sync de-assert |
| `irq_i` | in | `N_SOURCES` | interrupt lines | **level-sensitive**, synchronous to `clk_i`. Any CDC belongs in the accelerator socket (SPEC §20.1), never here |
| `lite_req_i` / `lite_rsp_o` | | `lite_req_t` / `lite_rsp_t` | I4 bus | frozen |
| `meip_o` | out | `N_TARGETS` | → `mip.MEIP` | level, combinational from pending ∧ enable ∧ priority > threshold |

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `N_SOURCES` | 16 | 2 … 1024 | **includes** the reserved source 0, so 16 means IDs 1–15 are usable |
| `N_TARGETS` | 1 | ≥ 1 | one per hart-privilege context |
| `PRIO_W` | 3 | ≥ 1 | priority levels are `1 … 2^PRIO_W − 1`; 0 is "never" |


## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | — | `verif/unit/tb_meds_s1_plic.sv` |
