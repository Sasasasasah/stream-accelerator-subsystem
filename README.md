# Stream Accelerator Subsystem

## What Is This?

A self-contained RTL and C++ reference-model prototype of a stream-oriented accelerator subsystem. It integrates a Stream Register Fabric (SRF), a stream-facing Memory Subsystem (MEM), and a Stream Transformation Engine (SXM) through fixed-cycle producer/consumer interfaces. The project focuses on cycle-accurate data movement, explicit state ownership, and self-checking integration verification rather than production accelerator implementation.

## Architecture

```text
MEM Read
   |
   v  producer slot 0
SRF
   |
   v  fixed-cycle stream propagation
SXM
   |
   v  producer slot 1
SRF
   |
   v
Consumer
```

SRF is a statically scheduled stream fabric with deterministic East/West propagation. MEM accesses SRF through local producer/consumer slot 0. SXM consumes input segments and returns transformed segments through local producer/consumer slot 1. Integration glue is combinational and adds no pipeline stage; registered SRF columns retain the cycle-by-cycle latency model.

## What Is Implemented?

### Stream Register Fabric (SRF)

- Multi-column `leaf -> column -> fabric` hierarchy
- East/West directional propagation
- Local producer and consumer access
- Deterministic cycle-by-cycle movement under static scheduling

### Memory Subsystem (MEM)

- Stream-facing read and write interfaces
- 64-bit segment producer/consumer integration through slot 0
- Logical-bank, slice, group, hemisphere, and full-MEM hierarchy

### Stream Transformation Engine (SXM)

- Stream segment consumption and transformed-segment production
- Transpose and permute operations
- Slot 1 integration with SRF

## Verification

| Verification Level | Status |
| --- | --- |
| SRF standalone | PASS |
| MEM standalone | PASS |
| SXM standalone | PASS |
| SRF + MEM integration | PASS |
| SRF + SXM integration | PASS |
| SRF + MEM + SXM combined integration | PASS |
| MEM -> SRF -> SXM input boundary | PASS |
| SXM -> SRF output boundary | PASS |
| MEM -> SRF -> SXM -> SRF full loopback E2E | PASS |

## Quick Start

The RTL regression is intended for Windows with Icarus Verilog (`iverilog` and `vvp`). From the repository root, run:

```bat
scripts\run_personal_regression.bat
```

The script runs the combined integration regression and the full-loopback E2E regression, then prints:

```text
STREAM_ACCELERATOR_SUBSYSTEM TEST_PASS
```

C++ reference models are included under `cmodel/` for architectural cross-checking. This repository currently provides no single public CModel regression entry point.

## Documentation

- [Architecture](docs/architecture.md)
- [Integration Contract](docs/integration.md)
- [Verification Notes](docs/verification.md)

## Repository Structure

```text
rtl/       SRF, MEM, SXM, and integration RTL
cmodel/    C++ reference models grouped by subsystem
tb/        Standalone, integration, and E2E testbenches
scripts/   Combined-system and full-loopback regression entry points
docs/      Architecture, integration, and verification notes
```

## Scope / Non-Goals

This is an RTL/C++ architecture prototype for statically scheduled stream movement, MEM/SRF/transpose-permute integration, and self-checking verification. It is not a production accelerator, ISA or software stack, physical-design implementation, timing-closure project, tapeout-ready IP, or production protocol implementation.

## Relationship to Standalone Repositories

This repository is a self-contained integration snapshot of the SRF, memory, and transpose/permute blocks used for subsystem-level verification. Standalone repositories focus on individual blocks; this repository focuses on integration and end-to-end behavior. It intentionally does not use Git submodules.
