# Stream Accelerator Subsystem

## 项目简介

本项目实现一个基于 Stream Register Fabric (SRF) 的 stream-based accelerator subsystem prototype。系统由 Stream Register Fabric (SRF)、Memory Subsystem (MEM) 与 Stream Transformation Engine (SXM) 组成，并通过 RTL、CModel 和 End-to-End (E2E) Testbench 验证完整数据路径。

## Architecture Overview

```text
MEM -> SRF -> SXM -> SRF -> Consumer
```

MEM 使用 producer/consumer slot0；SXM 使用 producer/consumer slot1。SRF 是 static-scheduled stream fabric，提供 deterministic directional propagation，不使用 valid-ready、backpressure 或 retry/replay。

## Key Features

- Multi-column Stream Register Fabric
- Directional stream propagation
- Memory producer / consumer integration
- Stream transpose / permute engine
- Multi-slot local producer / consumer access
- Cycle-level deterministic behavior
- RTL / CModel co-verification
- End-to-End regression

## Repository Structure

```text
rtl/       SRF, MEM, SXM and integration RTL
cmodel/    C++ reference models grouped by subsystem
tb/        Standalone, integration and E2E Testbench sources
scripts/   System combined and full loopback Regression entry points
docs/      Architecture, interface integration and verification notes
```

## Verification

已通过以下 Regression：

- SRF standalone — PASS
- MEM standalone — PASS
- SXM standalone — PASS
- SRF + MEM integration — PASS
- SRF + SXM integration — PASS
- SRF + MEM + SXM combined integration — PASS
- MEM → SRF → SXM input boundary — PASS
- SXM → SRF output boundary — PASS
- MEM → SRF → SXM → SRF Full Loopback E2E — PASS

## Quick Start

环境：Windows、Icarus Verilog (`iverilog` / `vvp`)；CModel 使用 C++ compiler。

在工程根目录运行：

```bat
scripts\run_srf_mem_sxm_regression.bat
scripts\run_mem_srf_sxm_loopback_e2e.bat
```

或运行聚合入口：

```bat
scripts\run_personal_regression.bat
```
