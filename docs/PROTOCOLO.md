# Protocolo HID del DELUX M618XSD

Reconstruido a partir de **DELUX Office Driver v1.1** (`Mouse.exe`, SHA256 `8cee1fd9…5404`,
y `hiddriver_ms_4.dll`, SHA256 `f9efbf06…39f4`), descompilados con Ghidra 12.1.4.
Dentro del driver, el M618XSD corresponde al modelo interno `ms_4` (`device_4_text = "M618XSD"` en `lan.xml`).

> El paquete `M618XSD.zip` (2021, `Mouse Driver.exe`) **no** sirve para esta unidad: habla
> una interfaz `0xFF1C` que el mouse no expone. El paquete `M618XSD Ver1.13 Upgrade` es solo
> un actualizador de firmware.

## Dispositivos

| Modo | VID:PID | Producto |
|---|---|---|
| Cable | `1d57:fa28` | USB Gaming Mouse |
| Receptor 2.4G | `1d57:fa60` | 2.4G Wireless Device |
| Bluetooth LE | `045e:0028` | BT5.2Mouse2 (ver [Bluetooth](#bluetooth-le)) |

Interfaz `MI_02`, colecciones relevantes:

| Colección | Usage Page / Usage | Uso |
|---|---|---|
| `COL04` | `0x000B` / `0x0000` | **Configuración**: solo *feature reports* (máx. 134 bytes) |
| `COL03` | `0x000A` / `0x0000` | **Eventos**: input report `0x03` de 5 bytes |

`hiddriver.dll` (`FUN_10001d70`) elige el dispositivo por VID/PID y UsagePage `0x0B` (configuración)
o `0x0A` (eventos). Escribe con `HidD_SetFeature`; el driver nunca lee configuración del mouse.

## Formato general de escritura

```
[ReportID] [Largo] [0x01] [datos …] [checksum hi] [checksum lo]
```

- Checksum: suma de 16 bits de los bytes desde el índice 3 hasta el anterior al checksum.
- Se envía exactamente `tamaño del report + 1` bytes (lo que dicta el descriptor).
- **Pausa obligatoria de 500 ms entre comandos** (verificado en el mouse real): si el
  siguiente llega antes, el mouse lo descarta en silencio mientras guarda el anterior.
- El mouse confirma cada report con el evento `03 28 50 00 RID`: byte 3 = estado (0 = OK)
  y byte 4 = report ID confirmado.
- Por cable, una escritura por comando. Por receptor, hasta 10 reintentos cada 500 ms
  hasta recibir el ACK.

## Secuencia "Aplicar" (`FUN_00433cd0`)

1. **Inicio** `0x0C` (6 bytes): `0c 0a 01 fe 01 fe`
2. **DPI** `0x04` (52 bytes), `FUN_00433ff0`
3. **Opciones/Luz** `0x05` (13 bytes)
4. **Polling** `0x06` (9 bytes)
5. **Botones** `0x08` (59 bytes), `FUN_00434690`
6. **Macros** `0x09` (3 × 64 bytes por botón con macro), `FUN_00434400`

### `0x04` DPI (52 bytes)

| Índice | Contenido |
|---|---|
| 0–2 | `04 38 01` |
| 3–4 | `00 00` |
| 5 | bitmask de niveles habilitados (bit i = nivel i) |
| 6, 7 | bitmask de niveles con DPI > 2400 (repetido) |
| 8–15 | byte bajo del DPI de cada nivel (8 niveles) |
| 16–23 | byte alto del DPI de cada nivel |
| 24 | nivel activo (1-based) |
| 25–48 | color RGB de cada nivel (8 × 3) |
| 49 | `02` |
| 50–51 | checksum (bytes 3–49) |

La UI guarda el DPI como `DPI / 40`: el perfil por defecto `[20, 30, 45, 60, 100]` equivale a 800/1200/1800/2400/4000.

### `0x05` Opciones y luz (13 bytes)

| Índice | Contenido |
|---|---|
| 0–2 | `05 0f 01` |
| 3 | `(luzAlMoverDesactivada << 7) \| modoLuz` |
| 4 | `(suspensión & 0xF0) \| (9 − velocidadRespiración)` |
| 5 | `((suspensión & 0x0F) << 4) \| (brillo & 0x0F)` |
| 6–8 | color RGB de la luz |
| 9 | temporizador de apagado de luz |
| 10 | tiempo de respuesta de teclas (debounce) |
| 11–12 | checksum (bytes 3–10) |

Modos de luz (`ms_lightmode1…12` en `lan.xml`): 0 = apagado, 1 = ola arcoíris, 2 = neón,
3 = respiración, 4 = salto de color, 5 = color fijo, 6 = respiración mixta, 7 = ola arcoíris 2,
8 = relámpago, 9 = mezcla fija, 10 = marquesina, 11 = marquesina 2.

### `0x06` Polling (9 bytes)

`06 09 01 R ~R 00 00 00 00`, con R = 8 / 4 / 2 / 1 para 125 / 250 / 500 / 1000 Hz.

### `0x08` Botones (59 bytes)

`08 3b 01`, después 18 ranuras × 3 bytes `[código, b1, b2]` y el checksum (bytes 3–56) en 57–58.

Cada ranura guarda un *ID de función* que se traduce con la tabla de `Mouse.exe` (`0x447778`).
Casos especiales:
- ID `0x10` (atajo personalizado): `[0x11, modificadores, tecla HID]`. Modificadores: 1 = Ctrl, 2 = Shift, 4 = Alt, 8 = Win/Cmd.
- ID `0x11` (macro): `[0x12, 0x00, ranura+1]`.

Asignación por defecto de las ranuras: 0 = izquierdo, 1 = derecho, 2 = adelante, 3 = atrás,
4 = central, 5 = DPI, 14/15 = inclinación izq./der., 16/17 = rueda arriba/abajo.

### `0x09` Macro (3 × 64 bytes)

Bloque lógico de 131 bytes: `09 83 ranura modo n n n x [20 × 00] cantidad [pares…] ck_hi ck_lo`.
Cada evento ocupa 2 bytes: `[(round(retardo/10) | 0x01 si se pulsa, | 0x81 si se suelta), tecla HID]`.
Si el retardo es ≥ 1271 ms, se añade el par `[retardo/200, 0x03]`.
Se envía troceado: `09 40 ranura k` más 60 bytes del bloque (k = 0, 1, 2).

## Bluetooth LE

Por Bluetooth el driver de Windows no usa HID, sino GATT (`FUN_00406d00`, `BluetoothGATTSetCharacteristicValue`).
Lo comprobé en el mouse real desde macOS con CoreBluetooth:

| Servicio | Característica | Propiedades | Uso |
|---|---|---|---|
| `FEE0` | `FEE3` | write | comandos (escritura con respuesta) |
| `FEE0` | `FEE4` | notify | eventos/ACK: `28 TT VV VV` (como por USB, sin el `03`) |
| `FEE0` | `FEE1`, `FEE2`, `FEE5` | read / writeNoResp / indicate | sin uso conocido |
| `F000FFC0-…` | `FFC1`, `FFC2` | write, notify | actualización de firmware de TI (OAD), **no tocar** |

Diferencias con HID:
- Cada paquete se envía con el largo que indica su byte 1: inicio 10, DPI 56, luz 15, botones 59.
- No se envía el polling (`0x06`).
- Cada macro va en un único bloque de 131 bytes, sin trocear.
- Se mantiene la pausa de 500 ms; el ACK llega por `FEE4`.

## Eventos (input `0x03`, colección `0x0A`)

`03 28 TT VV VV`: el byte 1 es el modelo (`0x28` = M618XSD) y TT es el tipo de evento:

| TT | Significado |
|---|---|
| `0x10` | cambio de nivel DPI (VV = nivel 1–8) |
| `0x20` | cambio de polling |
| `0x40` | batería / carga |
| `0x50` | **ACK** de comando: byte 3 = estado (0 = aceptado), byte 4 = report ID |
| `0x70`, `0x90` | cambio de modo de luz |
