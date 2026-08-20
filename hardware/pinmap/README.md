# 引脚映射与硬件连接清单（占位）

> 本文件在 **Task 2** 填充。当前仅为骨架占位。

## 目标产出

- 5 个茶轴按键 / 5 向摇杆 / ST7789 SPI / 背光 /（预留）音频的确定 GPIO 分配
- 避开已占用引脚：P9（用户 LED）、P29（用户按键）
- 供 jlceda-mcp 使用的网表 / 连接清单
- 引脚冲突校验脚本

## 输入依据

- T5 Pinmux 官方文档
- T5AI-Core 原理图（`../../components/T5AI-Core/T5AI-Core_V101-SCH.pdf`）

## 设计约定（待 Task 2 确认）

- LCD 使用硬件 SPI
- 按键直连 GPIO，启用内部上拉
