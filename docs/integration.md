# Integration Contract

## MEM-SRF Integration

MEM read output connects to SRF local producer slot 0. MEM write consumption connects to SRF local consumer slot 0. MEM uses SRF boundary state as the stream-facing write input.

## SRF-SXM Integration

SXM reads data, valid, direction, stream, and selector information from an SRF boundary. SXM consumption is issued through local consumer slot 1. Transformed output returns to SRF through local producer slot 1.

East SXM reads use sreg14. West SXM reads use sreg15.

## Slot Mapping

| Function | SRF Slot |
| --- | --- |
| MEM read producer | slot 0 |
| MEM write consumer | slot 0 |
| SXM output producer | slot 1 |
| SXM input consumer | slot 1 |

## Data Packing

One segment contains eight 8-bit lanes and is packed into 64 bits.

| Lane | Data Bits |
| --- | --- |
| lane0 | `data[7:0]` |
| lane1 | `data[15:8]` |
| lane2 | `data[23:16]` |
| lane3 | `data[31:24]` |
| lane4 | `data[39:32]` |
| lane5 | `data[47:40]` |
| lane6 | `data[55:48]` |
| lane7 | `data[63:56]` |

Segment valid requires the lane-valid condition defined by the current integration contract. A partial lane-valid segment is not treated as a fully valid segment.

## Valid and Consume Semantics

Data and valid propagate together through SRF. A successful consumer request clears the valid state for the consumed segment so that it does not continue passive propagation.

## Cycle Contract

Integration glue is a 0-cycle combinational mapping. It introduces no extra pipeline stage. Producer candidates are committed by the SRF cycle model, and committed stream data moves one SR column per cycle in the selected direction.

## End-to-End Path

The full loopback path is:

```text
MEM read -> slot 0 -> SRF -> SXM -> slot 1 -> SRF -> Consumer
```

The integration contract does not introduce additional flow-control, recovery, or scheduling mechanisms.
