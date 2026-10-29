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
- `--test` use simulated transport

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
