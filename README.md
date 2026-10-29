# HFI WSS CLI

This repository is the application/implementation repo for the HFI WSS Python CLI.

The reusable wrapper library lives in the `wss-py-wrapper` repository and is consumed here as a git submodule at `external/wss-py-wrapper/`.

## Repository Layout

- `src/wss_cli/`: app-owned CLI entry point
- `Config/`: app-owned runtime configuration JSON files
- `external/wss-py-wrapper/`: reusable wrapper library submodule

## Setup

Clone the app repo and initialize the wrapper submodule:

```bash
git clone --recursive git@github.com:cwru-non-academic/HFI_WSS_Python_Implementation_CLI.git
cd HFI_WSS_Python_Implementation_CLI
```

Create a virtual environment and install the app repo:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e external/wss-py-wrapper
python -m pip install -e .
```

The CLI can also import the wrapper directly from the checked-out submodule during editable app development, but installing the wrapper repo explicitly is the cleaner setup.

## Runtime Assets

- App-owned config location: `Config/` in this app repo
- Wrapper-owned DLL location: `external/wss-py-wrapper/Cs_Libraries/`

The CLI now constructs `WssConfig` explicitly from app-repo paths instead of relying on the old combined-repo current-working-directory layout.

## Run

```bash
wss-cli --help
wss-cli
wss-cli --test
```

Useful options:

- `--config PATH` override the config directory
- `--cs-libs PATH` override the DLL directory
- `--log-file PATH` override the log file path
- `--serial NAME` set the serial device
- `--max-retries N` set setup retries
- `--tick MS` set the tick interval
- `--transport serial|ble|test|conformance` selects the transport (case-insensitive)
- `--test` is an alias for `--transport=test`
- `--conformance` is an alias for `--transport=conformance`; it runs Core's initialization and direct-analog validators once, then exits with status 0 on success or 1 on failure
- `--serial-smoke` constructs and disposes the production serial transport with an explicit diagnostic port, without opening it
- `--ble-device-name NAME`, `--ble-device-id ID`, or `--ble-auto` explicitly selects a BLE target when using `--transport=ble`

Serial remains the default. BLE selectors cannot be combined with serial, test or
conformance options. Conformance creates a temporary calibration/configuration
fixture from shared Core scenarios; it does not edit the supplied `--config`
directory. Test mode keeps the interactive console running with Core's simulated
transport. Retry and tick defaults remain 5 and 10 ms, matching the C# CLI.

On macOS, select CoreCLR before starting the installed application, for example:

```bash
PYTHONNET_RUNTIME=coreclr wss-cli --transport=ble --ble-device-name WSS
```

The payload must include `backends/macos/WSS.Transport.BLE.MacOS.dll` and its
paired `libwss_macos_ble.dylib`. The existing wrapper loads this backend through
Core's transport factory and rejects missing files. Platform CI checks real
constructor/loading paths for all selectors on Windows, Ubuntu and macOS,
including BLE name/ID/auto selection. These checks do not scan for a device,
connect, or validate physical stimulation. Default serial auto-selection still
requires a real serial port inventory; the safe construction check uses an
explicit diagnostic port.

## Notes

- The CLI imports `WssConfig` and `StimulationController` from `wss_py_wrapper`.
- The default DLL path is `external/wss-py-wrapper/Cs_Libraries/`, which is owned by the wrapper repo.


## Conformance and automatic dependency promotion

See [.github/PYTHON_AUTOMATION.md](.github/PYTHON_AUTOMATION.md) for canonical tests, CLI coverage, CI checks and dev dependency promotion.
# Explicit BLE transport

Use `wss-cli --transport=ble --ble-device-name WSS`,
`--ble-device-id <identifier>`, or `--ble-auto`. Serial remains the default and
the existing `--serial`/`--test` options remain available. BLE requires the matching
packaged platform backend; selecting it initializes/connects only in normal user
operation. CI checks construction and loading without device I/O. See
[.github/MACOS_BLE_RECEIVER.md](.github/MACOS_BLE_RECEIVER.md) for the macOS payload
and reviewed promotion boundary.

## Device addresses and setup diagnostics

`Config/stimConfig.json` exposes Core's receiver-address settings:
`broadcastTarget` defaults to `"0x8F"`, and `wssTargets` defaults to
`["0x81", "0x82", "0x83"]` for logical Wss1, Wss2 and Wss3. These are receiver
addresses, not the host sender byte. Set the targets for your actual device
configuration (for example, an installation may need `"0x80"` for Wss1).
Existing configurations without these fields use Core's historical defaults;
these template changes do not rewrite existing user configuration. Core keeps
its existing normalization behavior for invalid address values.
Keep the firmware and calibration values appropriate to your hardware.

After changing receiver addresses, stop and restart the application so Core
constructs a new address map. The CLI `reload-core` command does not rebuild that map.
Setup continues asynchronously after controller initialization. An initialized
application or an advancing tick loop does not establish that a device is ready.
Core setup and tick errors are recorded in the configured log file; check the
reported absolute config and log paths when diagnosing connection failures.

The default config path is relative to the application's source layout, not the
current terminal directory. For a wheel installed outside an editable checkout,
pass `--config /path/to/your/Config` and `--cs-libs /path/to/Cs_Libraries`
explicitly: the wheel does not package the app-owned calibration/config files.
Startup prints these resolved paths before initialization and warns if
`stimConfig.json` is missing; Core may then create defaults, which are not a
substitute for your installation's calibrated configuration.
