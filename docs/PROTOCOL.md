# DELUX M618XSD HID protocol

Reconstructed from **DELUX Office Driver v1.1** (`Mouse.exe`, SHA256 `8cee1fd9…5404`,
and `hiddriver_ms_4.dll`, SHA256 `f9efbf06…39f4`), decompiled with Ghidra 12.1.4.
Inside the driver, the M618XSD is internal model `ms_4` (`device_4_text = "M618XSD"` in `lan.xml`).

> The `M618XSD.zip` package (2021, `Mouse Driver.exe`) does **not** work with this unit: it
> talks to a `0xFF1C` interface that the mouse does not expose. The `M618XSD Ver1.13 Upgrade`
> package is only a firmware updater.

## Devices

| Mode | VID:PID | Product |
|---|---|---|
| Cable | `1d57:fa28` | USB Gaming Mouse |
| 2.4G receiver | `1d57:fa60` | 2.4G Wireless Device |
| Bluetooth LE | `045e:0028` | BT5.2Mouse2 (see [Bluetooth](#bluetooth-le)) |

Interface `MI_02`, relevant collections:

| Collection | Usage Page / Usage | Purpose |
|---|---|---|
| `COL04` | `0x000B` / `0x0000` | **Configuration**: feature reports only (max. 134 bytes) |
| `COL03` | `0x000A` / `0x0000` | **Events**: 5-byte input report `0x03` |

`hiddriver.dll` (`FUN_10001d70`) selects the device by VID/PID and UsagePage `0x0B`
(configuration) or `0x0A` (events). It writes with `HidD_SetFeature`; the driver never reads
the configuration back from the mouse.

## General write format

```
[ReportID] [Length] [0x01] [data …] [checksum hi] [checksum lo]
```

- Checksum: 16-bit sum of the bytes from index 3 up to the byte before the checksum.
- Exactly `report size + 1` bytes are sent (as dictated by the descriptor).
- **Mandatory 500 ms pause between commands** (verified on the real mouse): if the next one
  arrives earlier, the mouse silently drops it while it stores the previous one.
- The mouse acknowledges each report with the event `03 28 50 00 RID`: byte 3 = status
  (0 = OK) and byte 4 = acknowledged report ID.
- Over cable, one write per command. Over the receiver, up to 10 retries every 500 ms until
  the ACK arrives.

## "Apply" sequence (`FUN_00433cd0`)

1. **Start** `0x0C` (6 bytes): `0c 0a 01 fe 01 fe`
2. **DPI** `0x04` (52 bytes), `FUN_00433ff0`
3. **Options/Lighting** `0x05` (13 bytes)
4. **Polling** `0x06` (9 bytes)
5. **Buttons** `0x08` (59 bytes), `FUN_00434690`
6. **Macros** `0x09` (3 × 64 bytes per button with a macro), `FUN_00434400`

### `0x04` DPI (52 bytes)

| Index | Contents |
|---|---|
| 0–2 | `04 38 01` |
| 3–4 | `00 00` |
| 5 | bitmask of enabled stages (bit i = stage i) |
| 6, 7 | bitmask of stages with DPI > 2400 (repeated) |
| 8–15 | low byte of each stage's DPI (8 stages) |
| 16–23 | high byte of each stage's DPI |
| 24 | active stage (1-based) |
| 25–48 | RGB color of each stage (8 × 3) |
| 49 | `02` |
| 50–51 | checksum (bytes 3–49) |

The Windows UI stores DPI as `DPI / 40`: the default profile `[20, 30, 45, 60, 100]` equals
800/1200/1800/2400/4000.

### `0x05` Options and lighting (13 bytes)

| Index | Contents |
|---|---|
| 0–2 | `05 0f 01` |
| 3 | `(lightOffWhileMoving << 7) \| lightMode` |
| 4 | `(sleep & 0xF0) \| (9 − breathingSpeed)` |
| 5 | `((sleep & 0x0F) << 4) \| (brightness & 0x0F)` |
| 6–8 | lighting RGB color |
| 9 | light-off timer |
| 10 | button response time (debounce) |
| 11–12 | checksum (bytes 3–10) |

Lighting modes (`ms_lightmode1…12` in `lan.xml`): 0 = off, 1 = rainbow wave, 2 = neon,
3 = breathing, 4 = color jump, 5 = static color, 6 = mixed breathing, 7 = rainbow wave 2,
8 = flash, 9 = static mix, 10 = marquee, 11 = marquee 2.

### `0x06` Polling (9 bytes)

`06 09 01 R ~R 00 00 00 00`, where R = 8 / 4 / 2 / 1 for 125 / 250 / 500 / 1000 Hz.

### `0x08` Buttons (59 bytes)

`08 3b 01`, then 18 slots × 3 bytes `[code, b1, b2]` and the checksum (bytes 3–56) at 57–58.

Each slot holds a *function ID* translated through the table in `Mouse.exe` (`0x447778`).
Special cases:
- ID `0x10` (custom shortcut): `[0x11, modifiers, HID key]`. Modifiers: 1 = Ctrl, 2 = Shift,
  4 = Alt, 8 = Win/Cmd.
- ID `0x11` (macro): `[0x12, 0x00, slot+1]`.

Default slot assignment: 0 = left, 1 = right, 2 = forward, 3 = back, 4 = middle, 5 = DPI,
14/15 = tilt left/right, 16/17 = wheel up/down.

### `0x09` Macro (3 × 64 bytes)

131-byte logical block: `09 83 slot mode n n n x [20 × 00] count [pairs…] ck_hi ck_lo`.
Each event takes 2 bytes: `[(round(delay/10) | 0x01 on press, | 0x81 on release), HID key]`.
If the delay is ≥ 1271 ms, the pair `[delay/200, 0x03]` is added.
Sent in chunks: `09 40 slot k` plus 60 bytes of the block (k = 0, 1, 2).

## Bluetooth LE

Over Bluetooth the Windows driver does not use HID but GATT (`FUN_00406d00`,
`BluetoothGATTSetCharacteristicValue`). Verified on the real mouse from macOS with
CoreBluetooth:

| Service | Characteristic | Properties | Purpose |
|---|---|---|---|
| `FEE0` | `FEE3` | write | commands (write with response) |
| `FEE0` | `FEE4` | notify | events/ACK: `28 TT VV VV` (as over USB, without the `03`) |
| `FEE0` | `FEE1`, `FEE2`, `FEE5` | read / writeNoResp / indicate | no known use |
| `F000FFC0-…` | `FFC1`, `FFC2` | write, notify | TI firmware update (OAD), **do not touch** |

Differences from HID:
- Each packet is sent with the length given by its byte 1: start 10, DPI 56, lighting 15,
  buttons 59.
- Polling (`0x06`) is not sent.
- Each macro is sent as a single 131-byte block, not chunked.
- The 500 ms pause still applies; the ACK arrives on `FEE4`.

## Events (input `0x03`, collection `0x0A`)

`03 28 TT VV VV`: byte 1 is the model (`0x28` = M618XSD) and TT is the event type:

| TT | Meaning |
|---|---|
| `0x10` | DPI stage change (VV = stage 1–8) |
| `0x20` | polling change |
| `0x40` | battery / charging |
| `0x50` | command **ACK**: byte 3 = status (0 = accepted), byte 4 = report ID |
| `0x70`, `0x90` | lighting mode change |
