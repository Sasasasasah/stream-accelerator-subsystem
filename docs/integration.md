# Integration Contract

## MEM ↔ SRF

MEM read output 连接 SRF producer slot0；MEM write consume 连接 SRF consumer slot0。MEM segment、SRF superlane 和数据 packing 均为 64 bit。segment valid 仅在全部 8 个 lane valid 时有效。

## SRF ↔ SXM

SXM 从 SRF boundary 读取 data、valid、direction、stream 与 selector，并通过 consumer slot1 提交 consume。SXM output 以 producer slot1 写回 SRF。East read 使用 sreg14，West read 使用 sreg15。

## Data and Control Fields

每个 segment 由 8 个 8-bit lane 组成：lane0 对应 `data[7:0]`，lane7 对应 `data[63:56]`。direction 选择 East/West propagation；selector 标识 stream、superlane 与 boundary 位置。consume 成功后清除对应 valid，避免 passive propagation。

## Integration Rule

integration glue 是 0-cycle combinational mapping。SRF 维持 static scheduling；当前 contract 不包含 valid-ready、backpressure、retry/replay 或动态 arbitration。
