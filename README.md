# DELUX M618XSD para macOS

Driver no oficial para configurar el mouse **DELUX M618XSD** en macOS. DELUX solo publica
su driver (DELUX Office Driver) para Windows; esta app replica sus funciones a partir del
protocolo reconstruido de ese driver.

*Unofficial macOS configuration app for the DELUX M618XSD mouse (wired, 2.4 GHz receiver
and Bluetooth LE). Contributions welcome.*

## Funciones

- **DPI:** 8 niveles (40–4800 DPI), color de cada nivel y nivel activo.
- **Botones:** las funciones del driver de Windows y atajos de macOS (⌘) por botón.
- **Iluminación:** 12 modos, color, brillo, velocidad y apagado al mover.
- **Rendimiento:** polling de 125 a 1000 Hz, debounce, apagado de luz y suspensión.
- **Perfiles:** varios perfiles, importación del `pro.data` de Windows y JSON.
- **Conexión:** cable USB, receptor 2.4G y Bluetooth LE; la app elige sola.

Probado en el mouse real en los tres modos. Por Bluetooth el mouse no permite cambiar el
polling. Las macros son experimentales y solo se editan por JSON.

## Requisitos

- macOS 13 o posterior.
- Swift 5.10 o posterior (basta con las Command Line Tools: `xcode-select --install`).

## Compilar

```bash
cd DeluxDriver
./scripts/build-app.sh
```

Genera `DeluxDriver/build/DELUX M618XSD.app` (firma ad hoc) y la herramienta de línea de
comandos `DeluxDriver/build/deluxctl`. La primera vez que conectes por Bluetooth, macOS
pedirá permiso de Bluetooth para la app.

## Uso

Abre la app, ajusta el perfil y pulsa **Aplicar** (⌘↩). La configuración queda guardada
en el mouse.

Línea de comandos (cable o receptor):

```bash
deluxctl info                       # detecta el mouse
deluxctl dump perfil.json           # muestra los paquetes sin enviarlos
deluxctl apply perfil.json --yes    # envía el perfil
deluxctl listen 30                  # muestra eventos (DPI, batería…)
deluxctl import-windows pro.data    # importa un perfil de Windows
```

macOS solo permite Bluetooth a una app empaquetada; para aplicar por Bluetooth sin ventana:

```bash
open -W "DeluxDriver/build/DELUX M618XSD.app" --args --apply "$PWD/perfil.json" --log salida.txt
```

## Pruebas

```bash
cd DeluxDriver
swift run selftest
```

## Estructura

| Ruta | Contenido |
|---|---|
| `DeluxDriver/Sources/DeluxKit` | Protocolo, modelo de perfil, HID (IOKit) y Bluetooth (CoreBluetooth) |
| `DeluxDriver/Sources/DeluxDriverApp` | App SwiftUI |
| `DeluxDriver/Sources/deluxctl` | Herramienta de línea de comandos |
| `DeluxDriver/Sources/selftest` | Pruebas |
| `docs/PROTOCOLO.md` | Especificación del protocolo (HID y Bluetooth) |
| `reference/windows-driver` | Perfil de fábrica exportado del driver de Windows (fixture de pruebas) |

## Contribuir

Se aceptan issues y pull requests. Pendientes conocidos:

- Editor de macros en la app y verificación de los campos de modo/repetición.
- Lectura de la configuración actual del mouse (el driver de Windows no la lee).
- Soporte de otros modelos DELUX con el mismo protocolo.

Antes de enviar un cambio, ejecuta `swift run selftest`. Si tocas el protocolo, prueba en
el mouse real y actualiza `docs/PROTOCOLO.md`.

## Aviso

Proyecto independiente, sin relación con DELUX. Se distribuye sin garantía; úsalo bajo tu
propio riesgo. No incluye software de DELUX.

## Licencia

[MIT](LICENSE)
