# Architecture

## 总体数据路径

系统主路径为 `MEM -> SRF -> SXM -> SRF -> Consumer`。MEM 读结果以 producer candidate 进入 SRF；SRF 将数据沿固定方向传播至 SXM input boundary；SXM 完成 stream transform 后，经 producer candidate 返回 SRF，再由 downstream consumer 使用。

## SRF Topology

SRF 使用 `leaf -> column -> fabric` hierarchy。leaf 是唯一的 data/valid state holder；column 是无状态结构 wrapper；fabric 提供固定延迟的 East/West directional propagation。该结构是 static scheduled，数据到达时刻由固定 pipeline 决定。

## MEM Attachment

MEM 的 64-bit segment 与 SRF 一个 superlane 对齐。MEM 作为 slot0 producer 提供 read result，并作为 slot0 consumer 消费写入数据。MEM 使用 SRF boundary state 作为写入侧输入。

## SXM Attachment

SXM 作为 SRF consumer 读取 input boundary，并作为 slot1 producer 将 transpose/permute 结果写回 SRF。SXM East input 对应 sreg14，West input 对应 sreg15。

## Cycle-level Data Flow

integration glue 为 0-cycle combinational mapping。每个 SRF registered column 提供一个固定 propagation stage；MEM/SXM 仅通过既有 producer/consumer contract 连接，不引入 arbitration、scheduler、backpressure 或 retry/replay。
