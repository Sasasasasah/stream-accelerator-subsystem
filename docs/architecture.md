# Architecture

## System Overview

The subsystem data path is:

```text
MEM -> SRF -> SXM -> SRF -> Consumer
```

MEM read results enter SRF as producer candidates. SRF propagates stream data to an SXM input boundary. SXM transforms the received stream segment and returns a producer candidate to SRF for downstream consumption.

## SRF Topology

SRF uses a `leaf -> column -> fabric` hierarchy. A leaf is the only holder of data and valid state. A column is a stateless structural wrapper. The fabric connects registered columns into fixed-latency directional pipelines.

East traffic propagates from lower to higher column indices; West traffic propagates in the opposite direction. Each registered SR column contributes one propagation cycle. The fabric is statically scheduled, so movement follows the configured cycle model.

## MEM Attachment

MEM is attached to SRF through local producer/consumer slot 0. MEM read operations produce 64-bit stream segments, while MEM write operations consume segments observed at the SRF boundary. A MEM segment maps to one SRF superlane.

## SXM Attachment

SXM consumes stream segments from SRF and returns transformed segments through local producer/consumer slot 1. SXM supports transpose and permute operations. In the current prototype topology, the East and West inputs use fixed attachment columns 14 and 15 respectively. These attachment columns are configuration-specific examples, not a requirement of the general SRF concept.

## Producer and Consumer Slots

| Slot | Owner | Role |
| --- | --- | --- |
| slot 0 | MEM | Read producer and write consumer |
| slot 1 | SXM | Transform producer and input consumer |

The slot assignment is static. The integration layer does not implement dynamic slot allocation or arbitration.

## Cycle-Level Data Movement

Integration adapters are combinational and add no pipeline stage. Producer candidates are committed according to the SRF cycle model. Once committed, stream data advances one registered SR column per cycle in the selected direction. Consumer requests clear the corresponding valid state after successful consumption.
