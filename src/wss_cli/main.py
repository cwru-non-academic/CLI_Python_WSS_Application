"""Interactive CLI for the HFI WSS application repo."""

from __future__ import annotations

import argparse
import sys
from dataclasses import replace
from datetime import datetime
from pathlib import Path
from tempfile import TemporaryDirectory


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _ensure_wrapper_importable() -> None:
    try:
        import wss_py_wrapper  # noqa: F401

        return
    except ModuleNotFoundError as exc:
        wrapper_src = _repo_root() / "external" / "wss-py-wrapper" / "src"
        if wrapper_src.is_dir():
            sys.path.insert(0, str(wrapper_src))
            import wss_py_wrapper  # noqa: F401

            return
        raise ModuleNotFoundError(
            "Could not import 'wss_py_wrapper'. Initialize the submodule at "
            "external/wss-py-wrapper and install the wrapper repo, or run this CLI "
            "from the application checkout with the submodule present."
        ) from exc


_ensure_wrapper_importable()

from wss_py_wrapper import StimulationController, WssConfig


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="HFI WSS stimulation console")
    parser.add_argument(
        "--serial", dest="serial", help="Fully qualified serial device (auto-detect)."
    )
    parser.add_argument("--config", dest="config", help="Config directory path.")
    parser.add_argument(
        "--cs-libs", dest="cs_libs", help="Directory containing WSS DLL files."
    )
    parser.add_argument(
        "--log-file", dest="log_file", help="Path for the log output file."
    )
    parser.add_argument("--max-retries", dest="max_retries", type=int, default=5)
    parser.add_argument("--tick", dest="tick", type=int, default=10)
    diagnostics = parser.add_mutually_exclusive_group()
    diagnostics.add_argument("--test", dest="test_mode", action="store_true", help="Use Core's simulated test transport.")
    diagnostics.add_argument("--conformance", dest="conformance_mode", action="store_true", help="Run shared Core conformance once using an isolated in-memory fixture.")
    parser.add_argument("--transport", type=str.lower, choices=("serial", "ble", "test", "conformance"), default="serial")
    parser.add_argument("--serial-smoke", action="store_true", help="Construct and dispose the production serial transport without opening a port.")
    parser.add_argument("--ble-device-name", help="Exact advertised BLE device name.")
    parser.add_argument("--ble-device-id", help="Explicit BLE device identifier.")
    parser.add_argument("--ble-auto", action="store_true", help="Explicitly auto-select a compatible BLE device.")
    return parser


def _default_log_path(repo_root: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return repo_root / "logs" / f"wss_{timestamp}.log"


def _default_cs_lib_dir(repo_root: Path) -> Path:
    return repo_root / "external" / "wss-py-wrapper" / "Cs_Libraries"


def _print_command_help() -> None:
    print('Commands at the > prompt (<...> required; [...] optional):')
    print('  help                 Show this command reference.')
    print('  status               Query Ready/Started/ModeValid/BasicSupported.')
    print('  start                Request broadcast start for configured devices.')
    print('  stop                 Request broadcast stop (not channel-specific).')
    print('  stim <finger|chN> <magnitude>  Apply active model and channel parameters.')
    print('    Intended input: finite 0.0..1.0, not mA. Example: stim ch1 1.0')
    print('  analog <finger|chN> <pw> [amp] [ipi]  Direct values; bypass model/params.')
    print('    Integers: pw in us, amp in mA domain (default 3), ipi in ms (default 10).')
    print('    Example: analog ch1 50 1 10. Omitted amp/ipi: analog ch1 50')
    print('  reload-core          Reload stimConfig.json; restart for address changes.')
    print('  reload-params [path]  Reload current params or select a JSON file/directory.')
    print('  save-params          Write active params JSON to its current host file.')
    print('  quit|exit            Leave the console and clean up the controller.')
    print('Aliases: thumb=ch1, index=ch2, middle=ch3, ring=ch4, pinky/little=ch5.')
    print('Use channels available in your configuration. Setup is asynchronous.')
    print('Examples are for simulation with --test and a disposable config copy.')
    print('Values depend on firmware/calibration; requests do not prove physical output.')
    print('See README Interactive commands for input limits, paths and examples.')
    print('Reload paths cannot contain spaces; quoting is not supported.')


def _run_interactive_loop(controller: StimulationController, config: WssConfig | None = None) -> None:
    running = True

    try:
        while running:
            try:
                raw = input("> ").strip()
            except EOFError:
                break

            if not raw:
                continue

            parts = raw.split()
            cmd = parts[0].lower()

            try:
                if cmd == "help":
                    _print_command_help()
                elif cmd in ("quit", "exit"):
                    running = False
                elif cmd == "start":
                    controller.StartStimulation()
                    print("Stim start requested.")
                elif cmd == "stop":
                    controller.StopStimulation()
                    print("Stim stop requested.")
                elif cmd == "status":
                    print(
                        f"Ready={controller.Ready()}, Started={controller.Started()}, "
                        f"ModeValid={controller.isModeValid()}, BasicSupported={controller.BasicSupported}"
                    )
                    if config is not None:
                        print(f"Config: {config.config_path}; Core setup/tick log: {config.log_path}")
                elif cmd == "reload-core":
                    controller.LoadCoreConfigFile()
                    print("Core config reloaded.")
                elif cmd == "reload-params":
                    if len(parts) > 1:
                        controller.LoadParamsJson(parts[1])
                    else:
                        controller.LoadParamsJson()
                    print("Params reloaded.")
                elif cmd == "save-params":
                    controller.SaveParamsJson()
                    print("Params saved.")
                elif cmd == "stim":
                    if len(parts) < 3:
                        print("Usage: stim <finger|chX> <magnitude>")
                        continue
                    magnitude = float(parts[2])
                    controller.StimWithMode(parts[1], magnitude)
                elif cmd == "analog":
                    if len(parts) < 3:
                        print("Usage: analog <finger|chX> <pw> [amp] [ipi]")
                        continue
                    pw = int(parts[2])
                    amp = int(parts[3]) if len(parts) > 3 else 3
                    ipi = int(parts[4]) if len(parts) > 4 else 10
                    controller.StimulateAnalog(parts[1], pw, amp, ipi)
                else:
                    print("Unknown command. Type 'help' to list options.")
            except Exception as ex:
                print(f"Command failed: {ex}")
    finally:
        controller.StopStimulation()
        controller.Shutdown()


def create_controller(config: WssConfig) -> StimulationController:
    """Construct the production controller with the resolved CLI configuration."""
    return StimulationController(config)


def _config_from_args(args: argparse.Namespace, repo_root: Path) -> WssConfig:
    """Resolve CLI paths and transport options before starting a controller."""
    config_path = (
        Path(args.config).expanduser().resolve()
        if args.config
        else repo_root / "Config"
    )
    cs_lib_dir = (
        Path(args.cs_libs).expanduser().resolve()
        if args.cs_libs
        else _default_cs_lib_dir(repo_root)
    )
    log_path = (
        Path(args.log_file).expanduser().resolve()
        if args.log_file
        else _default_log_path(repo_root)
    )

    config = WssConfig(
        config_path=config_path,
        log_path=log_path,
        cs_lib_dir=cs_lib_dir,
        transport="ble" if args.transport == "ble" else "serial",
        ble_device_name=args.ble_device_name if args.ble_device_name and args.ble_device_name.strip() else None,
        ble_device_id=args.ble_device_id if args.ble_device_id and args.ble_device_id.strip() else None,
        ble_auto=args.ble_auto,
        serial_port=args.serial if args.serial and args.serial.strip() else None,
        test_mode=args.test_mode or args.transport == "test",
        conformance_mode=args.conformance_mode or args.transport == "conformance",
    )
    if args.max_retries and args.max_retries > 0:
        config = replace(config, max_setup_tries=args.max_retries)
    if args.tick and args.tick > 0:
        config = replace(config, tick_interval_ms=args.tick)
    return config


def main(argv: list[str] | None = None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]
    if "/?" in argv:
        argv = ["--help" if arg == "/?" else arg for arg in argv]
    args = _build_parser().parse_args(argv)
    try:
        if args.serial_smoke:
            # Match the C# diagnostic: no Initialize/Open/discovery/stimulation.
            args.transport = "serial"
            args.serial = "COM1" if sys.platform == "win32" else "/dev/ttyWssSmoke"
            args.ble_auto = args.test_mode = args.conformance_mode = False
            args.ble_device_name = args.ble_device_id = None
            config = _config_from_args(args, _repo_root())
            controller = create_controller(config)
            transport = None
            try:
                controller._load_dotnet()
                transport = controller._create_transport()
            finally:
                if transport is not None:
                    transport.Dispose()
                controller.Shutdown()
            print("Serial transport constructed and disposed successfully.")
            return 0
        config = _config_from_args(args, _repo_root())
        if config.conformance_mode:
            from .diagnostics import create_conformance_config, run_conformance

            with TemporaryDirectory(prefix="wss-cli-conformance-") as directory:
                config = replace(config, config_path=Path(directory))
                create_conformance_config(config.cs_lib_dir, config.config_path)
                config.log_path.parent.mkdir(parents=True, exist_ok=True)
                controller = create_controller(config)
                try:
                    controller.Initialize()
                    return run_conformance(controller)
                finally:
                    controller.Shutdown()
        return _run_configured(config)
    except Exception as exc:
        print(f"Startup failed: {exc}", file=sys.stderr)
        return 1


def _run_configured(config: WssConfig) -> int:

    config.config_path.mkdir(parents=True, exist_ok=True)
    config.log_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Config: {config.config_path}")
    print(f"Log file: {config.log_path}")
    print(f"DLLs: {config.cs_lib_dir}")
    if not (config.config_path / "stimConfig.json").is_file():
        print("Warning: stimConfig.json is missing; Core may create defaults. Check --config and your device/calibration settings.", file=sys.stderr)
    controller = create_controller(config)
    try:
        controller.Initialize()
    except BaseException:
        controller.Shutdown()
        raise
    print("HFI WSS controller initialized; device setup continues asynchronously.")
    if config.test_mode:
        print("Transport: test")
    elif config.transport == "ble":
        print(f"Transport: ble ({config.ble_device_id or config.ble_device_name or 'auto-select'})")
    else:
        print(f"Transport: serial ({config.serial_port or 'auto-detect'})")
    print(
        f"Mode valid: {controller.isModeValid()}, Ready: {controller.Ready()}, Basic API: {controller.BasicSupported}"
    )
    _print_command_help()
    _run_interactive_loop(controller, config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
