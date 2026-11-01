# meds_s1_gpio_sync

## Status
WIP — M-03. The implementation is exercised indirectly by the GPIO
core unit test. Dedicated CDC review and project-level lint evidence
remain outstanding.

## Purpose
Synchronizes eight independent asynchronous GPIO inputs through two
clocked stages. It provides the input sampling path used by the GPIO
core and contains no bus protocol logic.

## Interface
Inputs are clk_i, rst_ni and async_i[7:0]. The output is sync_o[7:0].
Reset assertion asynchronously clears both stages. Reset deassertion
must already be synchronized by the system reset controller.

## Behaviour

Each input bit passes through two registered stages. `sync_o` is driven
from the second stage, so an input change is observed after two active
clock edges under stable simulation conditions. The stage registers are
marked with the `ASYNC_REG` implementation attribute.

## Limitations
This is not debounce logic. It does not guarantee coherent sampling
of a multi-bit external value. Simulation cannot prove metastability
reliability; implementation constraints and CDC review remain necessary.

## Verification
The GPIO core test exercises the synchronization path indirectly.
Dedicated CDC review and physical implementation checks remain pending.