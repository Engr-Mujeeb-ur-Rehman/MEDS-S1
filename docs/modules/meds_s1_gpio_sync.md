# meds_s1_gpio_sync

## Status
WIP — M-03. This proposed implementation has not yet been simulated
or checked with the project lint configuration.

## Purpose
Synchronizes eight independent asynchronous GPIO inputs through two
clocked stages. It provides the input sampling path used by the GPIO
core and contains no bus protocol logic.

## Interface
Inputs are clk_i, rst_ni and async_i[7:0]. The output is sync_o[7:0].
Reset assertion clears both stages. Reset deassertion must already be
synchronized by the system reset controller.

## Limitations
This is not debounce logic. It does not guarantee coherent sampling
of a multi-bit external value. Simulation cannot prove metastability
reliability; implementation constraints and CDC review remain necessary.

## Verification
The GPIO core test exercises the synchronization path indirectly.
Dedicated CDC review and physical implementation checks remain pending.