# Python WSS CLI

An interactive console for WSS configuration, status, and stimulation commands, using the [Python integration library](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib#readme). For shared concepts and configuration, see the [WSS documentation hub](https://cwru-non-academic.github.io/WSS_Documentation/).

## Setup

You need Git, Python 3.9+, and a compatible .NET runtime with the same architecture as Python. Keep the complete bundled DLL/native backend payload in the submodule. See the library README for runtime selection; on macOS/Linux set `PYTHONNET_RUNTIME=coreclr` before launch.

```bash
git clone https://github.com/cwru-non-academic/CLI_Python_WSS_Application.git
cd CLI_Python_WSS_Application
git -c 'url.https://github.com/.insteadOf=git@github.com:' submodule update --init --recursive
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e external/wss-py-wrapper
python -m pip install -e .
```

The submodule command uses HTTPS for the SSH-style URLs stored in older submodule entries; it needs no global Git configuration change.

On Windows, use `py -m venv .venv` and `.\.venv\Scripts\Activate.ps1` instead of the two environment commands above. For an existing checkout, run `git submodule sync --recursive` and the same HTTPS submodule update command before installing.

## First run without hardware

```bash
wss-cli --help
wss-cli --test
```

At the prompt, enter `status` to inspect readiness, `help` for commands, and `quit` to shut down. `--test` selects simulated transport and does not open a serial/BLE connection. Allow setup to complete before issuing commands.

The app uses `Config/` for `stimConfig.json`, `stimParams.json`, and `modelConfig.json`; logs go to `logs/`. These paths are relative to the application checkout, not your shell's current directory.

## Run with a device

Review your app-owned configuration against the [configuration reference](https://cwru-non-academic.github.io/WSS_Documentation/apiDocs/conceptual/config-files-reference.html) first. Start serial explicitly, for example:

```bash
wss-cli --serial COM5
```

Replace `COM5` with your device, such as `/dev/ttyACM0` on Linux. To use BLE on Windows, Linux, or macOS:

```bash
wss-cli --transport ble --ble-device-name WSS
```

Use your device's exact advertised name, or `--ble-device-id` for its identifier. `--ble-auto` explicitly permits automatic selection. Keep `--test` separate from physical-transport options.

Useful overrides are `--config PATH`, `--cs-libs PATH`, `--log-file PATH`, `--max-retries N`, and `--tick MS`. Run `wss-cli --help` for the complete option list. The interactive `start`, `stop`, `stim`, and `analog` commands control output; `quit` stops stimulation and shuts down the controller.

To build your own Python application, start with the [library setup and simulated example](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib#readme). For topic-based control, see the [ROS application](https://github.com/cwru-non-academic/ROS_Python_WSS_Application#readme).
