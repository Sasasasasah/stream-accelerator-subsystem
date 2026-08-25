# Verification

## Standalone Verification

- `SRF CORE TEST_PASS`
- `MEM_FULL_REGRESSION TEST_PASS`
- `SXM_ALL_REGRESSION TEST_PASS`

## Subsystem Integration

- `SRF_MEM_INTEGRATION_REGRESSION TEST_PASS`
- `SRF_SXM_INTEGRATION TEST_PASS`

## System Integration

- `SRF_MEM_SXM_COMBINED_REGRESSION TEST_PASS`

The combined regression checks concurrent MEM and SXM traffic, slot isolation, column isolation, and the SRF cycle contract.

## Boundary Tests

The MEM-to-SRF-to-SXM input boundary path and the SXM-to-SRF output boundary path both pass their contract regression.

## End-to-End Verification

- `MEM_SRF_SXM_LOOPBACK_E2E TEST_PASS`

The full loopback E2E test covers the MEM slot 0 path, the SXM slot 1 path, 64-bit lane packing, the cycle contract, and consume behavior.

## Regression Entry Points

Run the system-level regression from the repository root:

```bat
scripts\run_personal_regression.bat
```

It executes the combined integration regression followed by the full loopback E2E regression. A successful run prints:

```text
STREAM_ACCELERATOR_SUBSYSTEM TEST_PASS
```
