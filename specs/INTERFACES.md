# MEDS-S1 Platform — Interface Specification

**Version:** 0.1 (DRAFT — not frozen)
**Owner:** Umer Shahid · **Backup:** _(assign before freeze)_
**Change policy:** Only Tier-3 architects may modify this file. Any change to a **frozen** section
requires a version bump, a deprecation note, and sign-off from every module owner whose module
implements it.

> This is the most important file in the repository. Everything else can be rewritten by the next
> cohort. This cannot — the moment two accelerators exist, changing it breaks both.

---

## 0. Interface inventory and freeze status

| ID | Interface | Between | Freeze target | Status |
|---|---|---|---|---|
| **I1** | MXIF-1.0 | core ↔ tightly-coupled coprocessor (MEDS-V, custom ALUs) | Phase 0 | draft |
| **I2** | MEM-REQ | core pipeline ↔ cache ↔ bus adapter | Phase 0 | draft |
| **I3** | AXI4 backbone | fabric ↔ memory, DMA, accelerator sockets | Phase 0 | draft |
| **I4** | AXI4-Lite subtree | fabric ↔ peripherals | Phase 0 | draft |
| **I5** | Accelerator socket | fabric ↔ loosely-coupled accelerator | Phase 1 | draft |
| **I6** | RVFI + RVFI-V | core/coprocessor → verification | Phase 0 | draft |
| **I7** | IRQ | peripherals → PLIC → core; CLINT → core | Phase 1 | draft |
| **I8** | Debug | DTM ↔ DM ↔ core | Phase 1 | draft |
| **I9** | SRAM wrapper | RTL ↔ FPGA BRAM / ASIC macro | Phase 1 | draft |
| **I10** | PMA / memory map | `soc.yaml` → everything | Phase 0 | draft |

Naming convention throughout: `<if>_<signal>_<i|o>`, active-low reset `rst_ni`, single clock `clk_i`
per domain. All handshakes are AXI-style `valid`/`ready`: **`valid` must not depend combinationally
on `ready`**, and once asserted `valid` must remain asserted with stable payload until `ready`.

---

## 1. I1 — MXIF-1.0 (MEDS eXtension InterFace)

### 1.1 What it is and why it is not just CV-X-IF

MXIF-1.0 is a **documented profile of the OpenHW CV-X-IF eXtension Interface**: same signal names,
same semantics, a defined subset, plus one clearly-marked MEDS extension.

We profile rather than adopt wholesale for one reason: MEDS-V's issue interface (published in
*Building a RISC-V Vector Processor*, Ch 8.4) has **no commit/kill channel**, because it assumed a
core that issues non-speculatively. Rather than force a rewrite of a published design, MXIF-1.0
makes that assumption a *stated requirement on the core*.

**Conformance claim:** a MXIF-1.0 coprocessor is a valid CV-X-IF coprocessor that additionally
assumes `commit_kill` is never asserted. A CV-X-IF coprocessor that handles `commit_kill` correctly
will work unmodified on a MXIF-1.0 core. The compatibility is one-way and that is deliberate.

### 1.2 The issue-point rule — the load-bearing requirement

> **R1.1 (normative).** The core shall assert `x_issue_valid` only when the offloaded instruction is
> architecturally certain to execute: all older branches resolved, all older potentially-faulting
> instructions committed, no pending interrupt taken ahead of it. Equivalently: **offload happens at
> the retire pointer.**
>
> **R1.2 (normative).** Consequently `x_commit_valid` is asserted in the cycle following
> `x_issue_valid && x_issue_ready`, always with `x_commit_kill == 0`.
>
> **R1.3 (normative).** The commit channel **shall be present in RTL** on both sides at v1.0, even
> though its behaviour is trivial. MXIF-1.1 will relax R1.1; the wires must already exist.

**Cost of R1.1:** ~2 cycles of additional offload latency versus issuing from decode. Negligible for
MEDS-V (instructions run tens to hundreds of cycles). Measurable but acceptable for single-cycle
custom ops in v1. Revisit in MXIF-1.1.

**Benefit:** no speculative side effects are possible; no coprocessor needs a shadow state or a
rollback path; MEDS-V is legal exactly as designed.

### 1.3 Signals

```systemverilog
// ---- Issue channel ---------------------------------------------------------
  output logic         x_issue_valid_o;    // R1.1: asserted only when non-speculative
  input  logic         x_issue_ready_i;
  output logic [31:0]  x_issue_instr_o;    // raw instruction word
  output logic [1:0]   x_issue_mode_o;     // current privilege mode
  output logic [3:0]   x_issue_id_o;       // transaction id; v1 issues in order
  output logic [63:0]  x_issue_pc_o;       // MEDS extension: for trace and debug
  output logic [2:0][63:0] x_issue_rs_o;   // rs1, rs2, rs3 values, forwarded by the core
  output logic [2:0]   x_issue_rs_valid_o;

  input  logic         x_issue_accept_i;   // coprocessor claims this instruction
  input  logic         x_issue_writeback_i;// it will write a scalar register
  input  logic         x_issue_dualwrite_i;// v1.0: shall be tied 0
  input  logic         x_issue_loadstore_i;// it will access memory (see §1.6)

// ---- Commit channel (trivial in v1.0, see R1.2/R1.3) -----------------------
  output logic         x_commit_valid_o;
  output logic [3:0]   x_commit_id_o;
  output logic         x_commit_kill_o;    // v1.0: shall be tied 0

// ---- Retire-permission channel (MEDS extension -- see 1.4a) ----------------
  input  logic         x_norollback_i;     // per-id: "cannot fault; you may retire me"
  input  logic [3:0]   x_norollback_id_i;

// ---- Result channel --------------------------------------------------------
  input  logic         x_result_valid_i;
  output logic         x_result_ready_o;
  input  logic [3:0]   x_result_id_i;
  input  logic [4:0]   x_result_rd_i;
  input  logic [63:0]  x_result_data_i;
  input  logic         x_result_we_i;      // write rd
  input  logic         x_result_exc_i;     // instruction faulted
  input  logic [5:0]   x_result_exccode_i; // standard mcause exception code

// ---- MEDS extension --------------------------------------------------------
  input  logic         x_idle_i;           // coprocessor fully drained (see §1.5)
```

`x_issue_pc_o` and `x_idle_i` are **MEDS extensions to CV-X-IF**, marked as such. Both correspond
directly to signals MEDS-V already defines (`vec_req_pc`, `vec_idle`).

### 1.4 Exception policy (normative)

- **R1.4.** A coprocessor may reject an instruction only by deasserting `x_issue_accept_i`. The core
  then raises `illegal instruction` itself. Rejection is combinational within the issue handshake.
- **R1.5.** After accepting, a coprocessor may report **at most one** fault, via `x_result_exc_i`
  with a standard `mcause` code. This fault is precise at **instruction granularity only** — the
  core's architectural state reflects all older instructions retired and this one not started.
  Partial execution (e.g. a vector store that wrote some elements before faulting) is **permitted**
  and shall be documented by the coprocessor.
- **R1.6.** `x_result_exccode_i` shall be a standard code. Custom codes require a `REGISTRY.md` entry.

R1.5 is deliberately aligned with MEDS-V scope contract §E.3 ("faults are precise at instruction
granularity only"). The two documents agree by construction; keep them that way.

### 1.4a Two-phase completion — how decoupling survives in-order retire

R1.1 says offload happens at the retire pointer. Taken alone that would be fatal: a vector
instruction that runs for 300 cycles would sit at the head of the completion buffer for 300 cycles,
no younger instruction could retire, the buffer would fill, and the pipeline would stall. The core
would be decoupled in name only — and the overlap in MEDS-V book §8.6 (cycles 4–9, "the whole
argument for decoupling") would never happen.

The fix is to separate **"this instruction can no longer fault"** from **"this instruction has
finished"**. They are different events and only the first one gates retire.

> **R1.9 (normative).** A coprocessor shall assert `x_norollback_i` for a given `id` once it has
> completed every check that could raise an exception for that instruction — address generation,
> PMA/PMP, alignment, register-group legality. After `x_norollback` for an `id`, the coprocessor
> **shall not** report `x_result_exc` for that `id`.
>
> **R1.10 (normative).** The core retires an offloaded instruction when:
> - `x_norollback` has been received for its id, **and**
> - if `x_issue_writeback` was asserted, `x_result_valid` has also been received.
>
> **R1.11 (normative).** `x_norollback` may be asserted in the same cycle as `x_issue_accept`
> (typical for arithmetic), or many cycles later (typical for memory operations, after address
> checks). It shall be asserted at most once per id, and always before or with `x_result_valid`.

**What this buys, concretely:**

| Instruction | `x_norollback` at | Retires at | Core meanwhile |
|---|---|---|---|
| `vadd.vv` (no scalar result, no memory) | accept cycle | accept + 1 | runs on immediately; lanes still computing |
| `vle32.v` (memory, no scalar result) | after address range checked against PMA/PMP | check + 1 | runs on; VLSU still fetching |
| `vsetvli` (writes `vl` to a scalar reg) | accept cycle | when `x_result_valid` arrives | **stalls** — inherent, once per strip-mine pass |
| `vmv.x.s`, `vcpop.m` | accept cycle | when `x_result_valid` arrives | stalls |

Only the third and fourth rows stall, which is exactly the set MEDS-V book §8.4 already identifies
("the scalar core must stall that instruction's writeback until the response arrives"). Everything
else overlaps fully. The 300-cycle vector op retires in two cycles and keeps running.

**The cost, stated honestly:** an instruction that has retired but is still executing is
architecturally invisible, so if it faults afterwards there is nothing to trap to. That is why R1.9
is a hard requirement and not advice. It obliges the coprocessor to do **eager fault checking** —
for a vector load, computing and checking the whole `vl`-derived byte range *before* issuing any
memory request. MEDS-V's VLSU must do that range computation anyway (book §8.6 warns explicitly
against fetching VLEN/8 bytes when `vl` is smaller, precisely because it could fault on an access
the program never made), so R1.9 formalises an obligation the design already has.

**Interrupts.** An interrupt may be taken while a coprocessor instruction is still executing. Since
that instruction has already retired, `mepc` correctly points past it. The handler must not assume
the coprocessor is idle; if it needs to, it executes `fence` (§1.5).

**Context switch.** A trap handler that switches context must wait for `x_idle` before saving
coprocessor state. Note this for the OS port; it is a Phase-5 concern but it is a consequence of
this decision, so it is recorded here.

### 1.5 Ordering, fences, and idle (normative)

| Event | Required core behaviour |
|---|---|
| Offloaded instruction writes a scalar register (`x_issue_writeback_i`) | Stall retire of that instruction until `x_result_valid_i` |
| `fence` | Stall until `x_idle_i` and the store buffer is empty |
| `fence.i` | As `fence`, plus I$ invalidate |
| Debug halt request | Enter debug mode only after `x_idle_i` |
| WFI | May be entered with the coprocessor busy |
| Scalar memory access while a coprocessor memory op is outstanding (v1.0) | **Stall.** See §1.6 |

The last row implements MEDS-V Ch 8.4's conservative v1 rule ("the scalar core stalls on any scalar
memory access while vector memory operations are outstanding — it costs performance, it is obviously
correct, and it is one comparator"). It is a **platform-wide** rule in v1.0, not a MEDS-V-specific
one, and it is the price of §1.6's M2 memory model. Measure it and report it.

### 1.6 Coprocessor memory access — the M2/M3 model

MXIF-1.0 does **not** carry the CV-X-IF memory channel. A coprocessor that needs bulk memory
bandwidth uses its own port, because routing MEDS-V's VLEN-wide traffic through a 64-bit scalar LSU
would defeat the purpose of the vector unit.

**Model M2 — v1.0 (normative):**

- The coprocessor exposes an **I2-compatible master** (§2), width up to the backbone width.
- Addresses are **physical**. Software running vector or accelerator code executes in **M-mode**, or
  in S/U-mode with identity mapping only.
- The port is **non-coherent** with the scalar D$. Shared buffers must be in a non-cacheable PMA
  region, or explicitly maintained with `Zicbom`.
- Ordering versus scalar memory is provided by the stall rule in §1.5, not by the fabric.

**Model M3 — Phase 5 target (normative on the v1 design):**

> **R1.7.** The page-table walker shall be implemented with **two arbitrated request ports** from
> v1.0, with port 1 tied off. Port 1 is reserved for a coprocessor-side TLB.
>
> **R1.8.** The coprocessor memory port's address field shall be documented as *physical in v1.0,
> virtual in v1.1+*, and the coprocessor shall not assume the two are the same.

R1.7 is the entire reason this section exists. A PTW with an unused second port costs an arbiter. A
PTW without one costs a rewrite of the MMU during the Linux bring-up phase, which is the worst
possible time to be rewriting the MMU.

### 1.7 Adapting MEDS-V to MXIF-1.0

| MEDS-V signal | MXIF-1.0 | Action |
|---|---|---|
| `vec_req_valid_i` / `vec_req_ready_o` | `x_issue_valid` / `x_issue_ready` | rename |
| `vec_req_instr_i` | `x_issue_instr` | rename |
| `vec_req_rs1_i` / `vec_req_rs2_i` | `x_issue_rs[0]` / `x_issue_rs[1]` | rename; `rs[2]` unused |
| `vec_req_pc` (book §8.4) | `x_issue_pc` | rename |
| `vs_enabled_i` | derived from `x_issue_mode` + `mstatus.VS` | core drives; keep the port |
| `vec_resp_valid_o` / `vec_resp_data_o` | `x_result_valid` / `x_result_data` | rename; add `x_result_ready` backpressure |
| `vec_resp_rd` (book §8.4) | `x_result_rd` | rename |
| `vec_resp_illegal_o` | `x_issue_accept` **or** `x_result_exc` | **split** — see below |
| `vec_idle_o` | `x_idle` | rename |
| — | `x_commit_*` | **add**, ignore `kill` |
| — | `x_norollback_*` | **add** — the only substantive new logic MEDS-V needs (§1.4a). For arithmetic, tie to accept. For the VLSU, assert once the `vl`-derived byte range has passed PMA/PMP/alignment checks. |
| `mem_req_*` / `mem_rsp_*` | I2 master (§2) | widen and formalise |

**The one real change:** MEDS-V's single `vec_resp_illegal` conflates two different things —
"I refuse this instruction" (a decode-time reject) and "this instruction faulted" (a runtime
exception). MXIF separates them (§1.4). MEDS-V's decoder already computes `decoder_illegal`
combinationally in `vec_decoder`, so it can drive `x_issue_accept` directly; runtime faults from the
VLSU drive `x_result_exc`. This is a strictly better design and worth the erratum.

**Action:** raise a MEDS-V book erratum against Ch 8.4 and Appendix E, and add
`ext/meds-v/meds_v_mxif_adapter.sv` to the platform repo. Estimated half a day of RTL, one day of
prose. **Do it while the MEDS-V RTL is a skeleton.**

### 1.8 Scalar-core obligations imposed by MEDS-V

These are requirements *on S1-Core* that exist because MEDS-V exists. They belong in `ISA_SPEC.md`
for v1.0, not "when we get to vectors":

1. `mstatus.VS` field implemented, with trap-on-access-when-Off. (`Zve32x` requires it.)
2. `misa.V` reporting, gated on whether a vector coprocessor is present in `soc.yaml`.
3. Forwarding of `rs1`/`rs2` **values** on issue — the coprocessor has no register file access.
4. Retire stall on `x_issue_writeback` (§1.5) — `vsetvli` returns `vl` to a scalar register, and the
   *next* instruction almost always consumes it. This synchronisation happens once per strip-mine
   iteration and is inherent; do not try to optimise it away in v1.
5. `fence` waits for `x_idle`.
6. Decoder must forward — not reject — opcodes `0x57` (OP-V), `0x07` (LOAD-FP) and `0x27` (STORE-FP)
   when a coprocessor is present. Note `0x07`/`0x27` are shared with scalar FP loads/stores; the
   `width` field disambiguates. Get this right in v1 even with no FPU, or retrofitting `F` later
   becomes painful.

---

## 2. I2 — MEM-REQ (internal memory protocol)

A simple valid/ready request-response protocol, OBI-like. **The pipeline shall not speak AXI
directly** — that would couple pipeline timing to bus latency permanently, and every future bus
change would touch the core.

```systemverilog
  output logic              mem_req_valid_o;
  input  logic              mem_req_ready_i;   // may depend on valid (single-cycle grant OK)
  output logic [63:0]       mem_req_addr_o;
  output logic              mem_req_we_o;
  output logic [DW/8-1:0]   mem_req_be_o;
  output logic [DW-1:0]     mem_req_wdata_o;
  output logic [2:0]        mem_req_size_o;    // log2 bytes, for PMA width checking
  output logic [1:0]        mem_req_mode_o;    // privilege, for PMP/PMA checks
  output logic [3:0]        mem_req_id_o;      // for out-of-order response

  input  logic              mem_rsp_valid_i;
  output logic              mem_rsp_ready_o;
  input  logic [3:0]        mem_rsp_id_i;
  input  logic [DW-1:0]     mem_rsp_rdata_i;
  input  logic              mem_rsp_err_i;     // bus error / PMA violation
  input  logic [1:0]        mem_rsp_errcode_i;
```

`DW` is a parameter: 64 for the scalar core's ports, up to backbone width for coprocessor ports.
Responses may return out of order with respect to requests; `id` disambiguates. v1 core issues one
outstanding request per port, but **the id field is present from day one** for the same reason the
commit channel is.

MEDS-V's current `mem_req_*` port is this protocol minus `size`, `mode`, `id`, `rsp_ready` and the
error path. Add them in the adapter.

---

## 3. I3/I4 — Bus fabric

| | Backbone | Peripheral subtree |
|---|---|---|
| Protocol | AXI4 | AXI4-Lite |
| Data width | **256 bit** (parameter; validate 256 and 64) | **64 bit** (ADR-0005) |
| Address width | 40 bit | 40 bit |
| ID width | 6 bit | — |
| Bursts | INCR up to 16 beats; WRAP for cache refill | none |
| Masters | core I$, core D$, coprocessor port, accelerator sockets ×N, debug module | bridge from backbone |
| Slaves | DRAM, on-chip SRAM, boot ROM, AXI-Lite bridge, accelerator MMIO | CLINT, PLIC, UART, SPI, GPIO, timers |
| Slave port | — | `lite_req_t` / `lite_rsp_t` from `meds_s1_lite_pkg` |
| Implementation | `pulp-platform/axi` crossbar | `pulp-platform/axi` lite xbar |

**The peripheral subtree is 64 bits wide, not 32.** `mtime` and `mtimecmp` are architecturally
64-bit and must move in one access, which is what §9 already assumed when it gave the `clint` region
`widths: [4, 8]`. Peripherals whose registers are 32-bit — the PLIC, UART, SPI, GPIO — are not
affected: `meds_s1_lite_regif` presents them a 32-bit register file and absorbs the byte lane in one
place.

**Every AXI4-Lite slave presents exactly two struct ports**, `lite_req_i` and `lite_rsp_o`, and no
others. A peripheral with one port per AXI signal cannot be wired by the generator, cannot be
swapped for another implementation, and grows a port every time the bus gains a signal. The bundle
is declared once in `rtl/fabric/meds_s1_lite_pkg.sv`; `meds_s1_lite_regif` is the adapter every
peripheral instantiates behind it, and `meds_s1_clint.sv` is the worked example.

**Bandwidth budget** (100 MHz, 256-bit backbone = 3.2 GB/s per master port, memory-limited in
aggregate). Every accelerator declares its demand here before it is accepted:

| Master | Budget | Notes |
|---|---|---|
| Core I$ + D$ refill | 0.3 GB/s | 64-bit port via downsizer |
| Coprocessor (MEDS-V) | 1.6 GB/s @ VLEN=128×1 lane; 6.4 GB/s @ VLEN=512×4 lanes | scales with config |
| Accelerator socket 0 | ≤ 3.2 GB/s | declared per accelerator |
| Debug module | negligible | |

An accelerator whose declared demand exceeds its budget is a **design review item**, not a merge.

---

## 4. I5 — Accelerator socket (loosely-coupled)

One frozen bundle. Every loosely-coupled accelerator presents exactly this and nothing else, so the
SoC infrastructure can be synthesised out-of-context and reused across accelerator rebuilds.

```systemverilog
module meds_s1_accel_socket
  import meds_s1_lite_pkg::*;
#(
  parameter int unsigned AXI_DW = 256,
  parameter bit          ASYNC  =   0   // 1 => accelerator has its own clock domain
)(
  input  logic  clk_i,        // fabric clock
  input  logic  rst_ni,
  input  logic  accel_clk_i,  // accelerator clock; tie to clk_i when ASYNC = 0
  input  logic  accel_rst_ni,

  // The accelerator's MMIO window: the same I4 bundle every peripheral presents
  // (§3).  LITE_DW is not a socket parameter -- the bus has one width, declared
  // once in meds_s1_lite_pkg.
  input  lite_req_t  cfg_req_i,
  output lite_rsp_t  cfg_rsp_o,

  AXI_BUS.Master     dma,     // AXI4 master: the accelerator's data path
  output logic       irq_o    // level-sensitive, to the PLIC
);
```

> The `cfg` port was `AXI_BUS.Slave` in draft 0.1. It is the struct bundle now, so that a socket and
> a peripheral present the same thing and the generator wires both the same way (ADR-0005). The
> `dma` port is unchanged and still open: the AXI4 backbone bundle is T-04's to declare, and R-07
> should not build against `AXI_BUS` until it does.

**Socket conventions (normative):**

1. **Clock domain crossing lives in the socket, not in the accelerator.** When `ASYNC = 1` the socket
   instantiates AXI CDC bridges. Accelerator authors shall not write synchroniser logic (per the
   coding standard's CDC rule).
2. **Register map convention** — every accelerator's `cfg` window begins:

   | Offset | Name | Access | Meaning |
   |---|---|---|---|
   | `0x00` | `ID` | RO | 32-bit accelerator identifier, allocated in `extensions/REGISTRY.md` |
   | `0x04` | `VERSION` | RO | `{major[15:0], minor[15:0]}` |
   | `0x08` | `CTRL` | RW | bit 0 `start`, bit 1 `abort`, bit 2 `irq_en` |
   | `0x0C` | `STATUS` | RO | bit 0 `busy`, bit 1 `done`, bit 2 `error` |
   | `0x10` | `IRQ_STATUS` | W1C | write-1-to-clear |
   | `0x14` | `CAPABILITY` | RO | feature bits, accelerator-defined |
   | `0x20+` | accelerator-specific | | |

   This costs nothing and means a generic probe routine in the BSP can enumerate every accelerator
   on the bus and print what it found. Do it from the first accelerator.
3. **IRQ is level-sensitive and cleared via `IRQ_STATUS`.** Edge-triggered interrupts across a CDC
   are a bug generator.
4. **The DMA master shall respect the declared bandwidth budget** (§3) and shall not issue to
   non-idempotent regions.
5. The socket instance count and each socket's base address come from `soc.yaml`.

---

## 5. I6 — RVFI and RVFI-V (verification interface)

Standard **RVFI** from `riscv-formal`, driven at retire, one channel per retiring instruction. This
one port serves Spike/Sail co-simulation, `riscv-formal` bounded model checking, and functional
coverage collection.

```systemverilog
  rvfi_valid, rvfi_order[63:0], rvfi_insn[31:0], rvfi_trap, rvfi_halt, rvfi_intr,
  rvfi_mode[1:0], rvfi_ixl[1:0],
  rvfi_rs1_addr[4:0], rvfi_rs1_rdata[63:0], rvfi_rs2_addr[4:0], rvfi_rs2_rdata[63:0],
  rvfi_rd_addr[4:0],  rvfi_rd_wdata[63:0],
  rvfi_pc_rdata[63:0], rvfi_pc_wdata[63:0],
  rvfi_mem_addr[63:0], rvfi_mem_rmask[7:0], rvfi_mem_wmask[7:0],
  rvfi_mem_rdata[63:0], rvfi_mem_wdata[63:0],
  rvfi_csr_<name>_rmask/wmask/rdata/wdata      // per CSR group
```

**RVFI-V — MEDS extension for vector state.** RVFI has no vector concept, so co-simulating MEDS-V
requires an added group, driven by the coprocessor and merged into the core's retire stream by
`rvfi_order`:

```systemverilog
  rvfi_v_valid,
  rvfi_v_vd_addr[4:0],
  rvfi_v_vd_wdata[VLEN-1:0],
  rvfi_v_vd_wmask[VLENB-1:0],       // byte granularity, so tail/mask policy is checkable
  rvfi_v_vtype[63:0], rvfi_v_vl[VL_W-1:0], rvfi_v_vstart[VL_W-1:0]
```

`vd_wmask` at byte granularity is the point: it is what lets the checker verify that an *undisturbed*
tail really was undisturbed, which is MEDS-V's documented implementation choice (scope contract §E.4)
and is otherwise invisible to a checker that only compares final register contents.

**Requirement:** RVFI is driven from **Phase 1**, before the first cache exists. Chapter 13 of the
MEDS-V book puts co-simulation at M2, "before any datapath exists", for exactly this reason. Build
the checker before the thing it checks.

---

## 6. I7 — Interrupts

- **CLINT** at the standard base: `msip` (software), `mtime`/`mtimecmp` (timer). Required for Linux.
- **PLIC** for external interrupts. Priority + threshold + claim/complete, standard layout.
- Interrupt source IDs are **allocated in `soc.yaml`** and generated into the device tree, the C
  headers and `memory_map.md`. Never hand-assign an IRQ number in two places.
- Accelerator sockets get IRQ IDs from the same allocator. Reserve IDs 1–15 for platform
  peripherals, 16+ for accelerators.
- All PLIC sources are **level-sensitive**.

---

## 7. I8 — Debug

RISC-V External Debug Support, via `pulp-platform/riscv-dbg` (DM + JTAG DTM).

Core-side obligations, which touch the pipeline and CSR file and are therefore **Phase-1
architectural requirements even though the DM lands in Phase 3**:

1. `DebugMode` as a state in the privilege FSM.
2. CSRs `dcsr`, `dpc`, `dscratch0`, `dscratch1`.
3. Halt request / resume request / halted status handshake.
4. Single-step (`dcsr.step`).
5. Trigger module (`tselect`, `tdata1/2/3`) — at least 2 hardware breakpoints. Instruction-address
   triggers minimum; data triggers are a bonus.
6. **Debug entry waits for `x_idle`** (I1 §1.5), so GDB never observes a partially-executed
   coprocessor instruction.
7. Abstract command support for register and memory access — this is what makes `load` over JTAG work.

Deliverables alongside: an `openocd.cfg` per board, and a semihosting handler so `printf` and
`fopen` reach the host filesystem (see the addendum, B6).

---

## 8. I9 — SRAM wrapper

```systemverilog
module meds_sram_wrapper #(
  parameter int unsigned DW    = 64,
  parameter int unsigned DEPTH = 1024,
  parameter int unsigned IMPL  = 0   // 0 = behavioural, 1 = FPGA BRAM, 2 = ASIC macro
)(
  input  logic clk_i, rst_ni,
  input  logic req_i, we_i,
  input  logic [$clog2(DEPTH)-1:0] addr_i,
  input  logic [DW/8-1:0]          be_i,
  input  logic [DW-1:0]            wdata_i,
  output logic [DW-1:0]            rdata_o   // registered, 1-cycle latency
);
```

**Normative:** no memory anywhere in the design may be inferred directly. Every array — register
file, cache tags, cache data, TLB, VRF, FIFOs above 32 entries — goes through this wrapper. This is
the single rule that makes an ASIC port possible later and it costs nothing now. Read latency is
**one cycle, registered output**, everywhere, no exceptions — a mixed-latency memory system is where
timing closure goes to die.

---

## 9. I10 — Memory map and PMAs

Single source of truth: `soc.yaml`. Generated into the RTL address decoder, `link.ld`,
`meds_s1_soc.h`, `meds_s1.dtsi`, `memory_map.md`, and the PMA check unit. **Never hand-edited in more
than one place.**

Every region carries the full PMA set:

```yaml
memory_map:
  - name: bootrom
    base: 0x0000_1000
    size: 32K
    type: rom
    pma: { cacheable: i-only, idempotent: true,  order: rvwmo,  atomic: none,
           align: natural,  widths: [4, 8] }

  - name: clint
    base: 0x0200_0000
    size: 64K
    type: device
    pma: { cacheable: false, idempotent: false, order: strong, atomic: none,
           align: natural,  widths: [4, 8] }

  - name: dram
    base: 0x8000_0000
    size: 1G
    type: memory
    pma: { cacheable: true,  idempotent: true,  order: rvwmo,  atomic: [lrsc, amo],
           align: any,      widths: [1, 2, 4, 8, 32] }

  - name: dram_uncached          # same physical DRAM, non-cacheable alias
    base: 0x1_0000_0000
    size: 1G
    alias_of: dram
    pma: { cacheable: false, idempotent: true,  order: strong, atomic: [amo],
           align: natural,  widths: [1, 2, 4, 8, 32] }

  - name: accel0
    base: 0x2000_0000
    size: 64K
    socket: 0
    irq: 16
    pma: { cacheable: false, idempotent: false, order: strong, atomic: none,
           align: natural,  widths: [4] }
```

**Normative PMA rules:**

- **P1.** A `idempotent: false` region shall never be speculatively accessed, prefetched, or
  replayed. The D$ and any future prefetcher must exclude such regions structurally, not by
  convention.
- **P2.** `order: strong` regions are accessed in program order with respect to each other, without
  requiring a `fence`. This is what makes an MMIO write to an accelerator's `CTRL.start` register
  safe after the descriptor writes that precede it.
- **P3.** An access violating a region's `align` or `widths` raises an access fault, not a silent
  truncation. MEDS-V requires natural EEW alignment (scope contract §E.3), so this rule is what
  turns its documented restriction into an enforced one.
- **P4.** The `dram_uncached` alias exists so accelerator-shared buffers work correctly before
  `Zicbom` is implemented. It costs one address-decode bit. Do not remove it once `Zicbom` lands —
  it stays useful for debugging coherence bugs.
- **P5.** PMA checks happen in the LSU, in parallel with PMP, before the request reaches the bus.

---

## 10. Change control

| Change | Requires |
|---|---|
| New signal, backward-compatible default | minor version bump; owner + one reviewer |
| Semantic change to an existing signal | major version bump; **all** implementing module owners sign off; deprecation note with a removal release |
| New interface | Tier-3 review; entry in §0 |
| Relaxing a normative requirement (R1.x, P1–P5) | design review; recorded in the decision log |

Each interface carries a version constant readable from RTL and software:

```systemverilog
  localparam logic [31:0] MXIF_VERSION      = 32'h0001_0000;  // 1.0
  localparam logic [31:0] MEDS_S1_PLATFORM_VERSION = 32'h0000_0100;
```

Expose `MEDS_S1_PLATFORM_VERSION` in the boot ROM and in a read-only CSR, so a driver can identify
what hardware it is talking to. A one-line change now that will save a confusing afternoon every
year for the next decade.

---

## Open questions before freeze

1. **`x_issue_id` width.** 4 bits (16 outstanding) is generous for a v1 core that issues one at a
   time. Keep 4 for headroom, or narrow to 2? — *Recommend 4; the cost is wires.*
2. **Backbone width 256 vs 512.** 256 covers every declared consumer in §3. 512 doubles crossbar
   area for headroom nothing currently needs. — *Recommend 256, parameterised.*
3. **Does the coprocessor port participate in PMP/PMA checks?** It must, or an accelerator can
   bypass PMP entirely and §D2's PMP differentiator is hollow. Where does the check unit live —
   in the coprocessor's port adapter, or in the fabric? — *Needs a decision. Recommend a shared
   check unit in the port adapter, so PMP config is core-owned.*
4. **RVFI-V merge order.** How does the coprocessor's retire stream interleave with the core's in
   `rvfi_order` when execution is decoupled? — *Needs a concrete proposal from the verification
   owner before Phase 1.*
5. **Do we need `Zicboz` (cache-block zero) alongside `Zicbom`?** Cheap, and useful for zeroing
   accelerator buffers. — *Recommend yes; it is on the RVA23 list anyway.*

---

*This file is DRAFT until the Phase-0 design review ratifies it. After that, §1 (MXIF), §2 (MEM-REQ),*
*§4 (accelerator socket), §5 (RVFI) and §9 (memory map / PMA) are* ***frozen*** *and changes follow*
*§10. Those five sections are the surfaces every attached accelerator depends on.*
