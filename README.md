# DELUX M618XSD for macOS

Unofficial macOS app to configure the **DELUX M618XSD** mouse. DELUX only ships its driver
(DELUX Office Driver) for Windows; this app reproduces its features from the protocol
reverse-engineered from that driver.

## Features

- **DPI:** 8 stages (40–4800 DPI), per-stage color and active stage.
- **Buttons:** the Windows driver's functions plus macOS (⌘) shortcuts per button.
- **Lighting:** 12 modes, color, brightness, speed and turn-off-while-moving.
- **Performance:** polling rate from 125 to 1000 Hz, debounce, light-off and sleep timers.
- **Profiles:** multiple profiles, import from the Windows `pro.data` file, and JSON.
- **Connection:** USB cable, 2.4 GHz receiver and Bluetooth LE; the app picks one automatically.

Tested on the real mouse in all three modes. Over Bluetooth the mouse does not allow
changing the polling rate. Macros are experimental and can only be edited as JSON.

## Requirements

- macOS 13 or later.
- Swift 5.10 or later (the Command Line Tools are enough: `xcode-select --install`).

## Build

```bash
cd DeluxDriver
./scripts/build-app.sh
```

This produces `DeluxDriver/build/DELUX M618XSD.app` (ad hoc signed) and the command-line
tool `DeluxDriver/build/deluxctl`. The first time you connect over Bluetooth, macOS will ask
for Bluetooth permission for the app.

## Usage

Open the app, adjust the profile and click **Apply** (⌘↩). The settings are stored
on the mouse itself.

Command line (cable or receiver):

```bash
deluxctl info                       # detect the mouse
deluxctl dump profile.json          # print the packets without sending them
deluxctl apply profile.json --yes   # send the profile
deluxctl listen 30                  # print mouse events (DPI, battery…)
deluxctl import-windows pro.data    # import a Windows profile
```

macOS only grants Bluetooth access to a bundled app; to apply a profile over Bluetooth
without opening a window:

```bash
open -W "DeluxDriver/build/DELUX M618XSD.app" --args --apply "$PWD/profile.json" --log output.txt
```

## Tests

```bash
cd DeluxDriver
swift run selftest
```

## Layout

| Path | Contents |
|---|---|
| `DeluxDriver/Sources/DeluxKit` | Protocol, profile model, HID (IOKit) and Bluetooth (CoreBluetooth) |
| `DeluxDriver/Sources/DeluxDriverApp` | SwiftUI app |
| `DeluxDriver/Sources/deluxctl` | Command-line tool |
| `DeluxDriver/Sources/selftest` | Tests |
| `docs/PROTOCOL.md` | Protocol specification (HID and Bluetooth) |
| `reference/windows-driver` | Factory profile exported from the Windows driver (test fixture) |

## Contributing

Issues and pull requests are welcome. Known open items:

- Macro editor in the app, and confirming the meaning of the mode/repeat fields.
- Localization of the user interface into other languages.
- Reading the mouse's current settings (the Windows driver never reads them).
- Support for other DELUX models that use the same protocol.

Before submitting a change, run `swift run selftest`. If you change the protocol, test on a
real mouse and update `docs/PROTOCOL.md`.

## Disclaimer

Independent project, not affiliated with DELUX. Provided without warranty; use at your own
risk. No DELUX software is included.

## License

[MIT](LICENSE)
