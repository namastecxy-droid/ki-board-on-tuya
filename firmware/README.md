# Firmware — T5AI-Core (TuyaOpen)

> Skeleton only. Real application logic lands in Phase 1 (Task 3+).

This directory hosts the T5AI-Core firmware built with the native **TuyaOpen SDK + `tos.py`**,
compiled natively on Windows (Git Bash, no WSL required).

## Target

- MCU: T5-E1 module (Arm Cortex-M33F @ 480 MHz, Wi-Fi6 + BLE 5.4)
- Display: CL28CK230-18A LCD (ST7789 driver, 320×240, SPI)
- Input: WS-1002 5-way switch + 5× mechanical keys (CPG151101D06 brown switch)
- Audio: onboard mic / speaker

## Planned structure (filled in by later tasks)

```text
firmware/
├── app/            # TuyaOpen application entry + business logic
├── src/            # input scan, state machine, transport, UI (LVGL/ST7789)
├── include/        # headers, pin definitions
└── README.md       # this file
```

## Notes

- Code comments in English (see repo dev rules).
- Transport layer is pluggable: UART (Phase 1) → BLE GATT (Phase 2) → BLE HID (Phase 3).
- The wire protocol is shared with the companion app; see `../shared/protocol/protocol.md`.
