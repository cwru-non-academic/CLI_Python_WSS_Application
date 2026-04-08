"""Interactive CLI for the HFI WSS application repo."""

from __future__ import annotations

import argparse
import sys
from dataclasses import replace
from datetime import datetime
from pathlib import Path


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
    parser.add_argument("--test", dest="test_mode", action="store_true")
    return parser


def _default_log_path(repo_root: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return repo_root / "logs" / f"wss_{timestamp}.log"


def _default_cs_lib_dir(repo_root: Path) -> Path:
    return repo_root / "external" / "wss-py-wrapper" / "Cs_Libraries"


def _print_command_help() -> None:
    print("Commands:")
    print("  help                Show this help text.")
    print("  start               Broadcast StartStim.")
    print("  stop                Broadcast StopStim.")
    print("  stim <finger> <v>   Stim with model/params layer (normalized magnitude).")
    print("  analog <finger> <pw> [amp] [ipi]  Send direct analog request.")
    print("  reload-core         Reload the core config JSON.")
    print("  reload-params [p]   Reload params JSON (optionally from path).")
    print("  save-params         Persist params JSON.")
    print("  status              Print Ready/Started/mode state.")
    print("  quit|exit           Terminate the program.")


def _run_interactive_loop(controller: StimulationController) -> None:
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


def main(argv: list[str] | None = None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]
    if "/?" in argv:
        argv = ["--help" if arg == "/?" else arg for arg in argv]

    parser = _build_parser()
    args = parser.parse_args(argv)

    repo_root = _repo_root()
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
    )
    if args.serial:
        config = replace(config, serial_port=args.serial)
    if args.max_retries and args.max_retries > 0:
        config = replace(config, max_setup_tries=args.max_retries)
    if args.tick and args.tick > 0:
        config = replace(config, tick_interval_ms=args.tick)
    if args.test_mode:
        config = replace(config, test_mode=True)

    config.config_path.mkdir(parents=True, exist_ok=True)
    config.log_path.parent.mkdir(parents=True, exist_ok=True)

    controller = StimulationController(config)
    controller.Initialize()
    print("HFI WSS stimulation controller ready.")
    print(f"Config: {config.config_path}")
    print(f"Log file: {config.log_path}")
    print(f"DLLs: {config.cs_lib_dir}")
    print(f"Serial: {config.serial_port or 'auto-detect'}")
    print(
        f"Mode valid: {controller.isModeValid()}, Ready: {controller.Ready()}, Basic API: {controller.BasicSupported}"
    )
    _print_command_help()
    _run_interactive_loop(controller)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
