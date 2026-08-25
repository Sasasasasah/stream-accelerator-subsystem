# Stream Accelerator Subsystem

## Overview

This repository implements a stream-based accelerator subsystem prototype built around a Stream Register Fabric (SRF). The subsystem integrates a Stream Register Fabric (SRF), a Memory Subsystem (MEM), and a Stream Transformation Engine (SXM).

The design is implemented in RTL and accompanied by C++ reference models, module-level testbenches, subsystem integration tests, and end-to-end regression.

## Architecture

```text
MEM
 |
 v
SRF
 |
 v
SXM
 |
 v
SRF
 |
 v
Consumer
```

MEM accesses SRF through local producer/consumer slot 0. SXM accesses SRF through local producer/consumer slot 1. SRF is a statically scheduled stream fabric with deterministic directional propagation.

## Components

### Stream Register Fabric (SRF)

- Multi-column stream register fabric
- East/West directional propagation
- Local producer and consumer access
- Deterministic cycle-by-cycle movement
- Static scheduling

### Memory Subsystem (MEM)

- Stream-facing memory subsystem
- Read operations produce stream data through slot 0
- Write operations consume stream data through slot 0

### Stream Transformation Engine (SXM)

- Consumes stream segments from SRF
- Performs transpose and permute operations
- Writes transformed data back to SRF through slot 1

## Data Flow

MEM read results enter SRF as producer candidates. SRF propagates the stream toward the SXM input boundary. SXM consumes a segment, transforms it, and returns the result to SRF as a producer candidate for downstream consumption.

The integration glue is combinational and adds no pipeline cycle. It does not make the subsystem zero-latency: SRF propagation still follows its registered column-by-column cycle model.

## Verification

| Verification Level | Status |
| --- | --- |
| SRF standalone | PASS |
| MEM standalone | PASS |
| SXM standalone | PASS |
| SRF + MEM integration | PASS |
| SRF + SXM integration | PASS |
| SRF + MEM + SXM combined integration | PASS |
| MEM → SRF → SXM input boundary | PASS |
| SXM → SRF output boundary | PASS |
| MEM → SRF → SXM → SRF full loopback E2E | PASS |

## Repository Structure

```text
rtl/       SRF, MEM, SXM, and integration RTL
cmodel/    C++ reference models grouped by subsystem
tb/        Standalone, integration, and E2E testbenches
scripts/   Combined-system and full-loopback regression entry points
docs/      Architecture, integration, and verification notes
```

## Quick Start

The project is intended for Windows with Icarus Verilog (`iverilog` and `vvp`). C++ reference models require a C++ compiler.

Run the combined integration and full loopback E2E regression from the repository root:

```bat
scripts\run_personal_regression.bat
```

The script runs the combined integration regression and the full loopback E2E regression, then prints:

```text
STREAM_ACCELERATOR_SUBSYSTEM TEST_PASS
```
