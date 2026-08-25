# Verification

## Standalone Verification

- `SRF CORE TEST_PASS`
- `MEM_FULL_REGRESSION TEST_PASS`
- `SXM_ALL_REGRESSION TEST_PASS`

## Subsystem Integration Verification

- `SRF_MEM_INTEGRATION_REGRESSION TEST_PASS`
- `SRF_SXM_INTEGRATION TEST_PASS`

## System Integration Verification

- `SRF_MEM_SXM_COMBINED_REGRESSION TEST_PASS`

## Boundary E2E Verification

MEM → SRF → SXM input boundary 与 SXM → SRF output boundary 的 contract Regression 均为 PASS。

## Full Loopback E2E Verification

- `MEM_SRF_SXM_LOOPBACK_E2E TEST_PASS`
- 覆盖 MEM slot0、SXM slot1、lane packing、Cycle Contract 与 consume behavior。

本仓库的 `scripts\run_personal_regression.bat` 只运行 system combined regression 与 full loopback E2E，成功时输出 `STREAM_ACCELERATOR_SUBSYSTEM TEST_PASS`。
