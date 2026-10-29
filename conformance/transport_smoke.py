"""Exercise CLI selectors through real managed transports, without radio/port I/O."""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
if importlib.util.find_spec("wss_cli") is None:
    sys.path.insert(0, str(ROOT / "src"))
os.environ.setdefault("PYTHONNET_RUNTIME", "coreclr")
from wss_cli import main as cli

parser = argparse.ArgumentParser()
parser.add_argument("--payload", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
payload = args.payload.resolve()
checked = []
with TemporaryDirectory(prefix="wss-cli-transport-check-") as directory:
    temp = Path(directory)
    supplied = temp / "user-config"
    supplied.mkdir()
    marker = supplied / "keep-user-config.txt"
    marker.write_text("unchanged")
    common = ["--cs-libs", str(payload), "--config", str(supplied), "--log-file", str(temp / "test.log")]
    cases = [
        (["--serial=COM7" if sys.platform == "win32" else "--serial=/dev/ttyWssSmoke"], "SerialPortTransport"),
        (["--test"], "TestModeTransport"), (["--transport=test"], "TestModeTransport"),
        (["--conformance"], "EmulatedWssTransport"), (["--transport=conformance"], "EmulatedWssTransport"),
        (["--transport=ble", "--ble-device-name=WSS-NO-RADIO"], "BleNusTransport"),
        (["--transport=ble", "--ble-device-id=00000000-0000-0000-0000-000000000001"], "BleNusTransport"),
        (["--transport=ble", "--ble-auto"], "BleNusTransport"),
    ]
    for flags, expected in cases:
        config = cli._config_from_args(cli._build_parser().parse_args(common + flags), ROOT)
        controller = cli.create_controller(config)
        transport = None
        try:
            controller._load_dotnet()
            transport = controller._create_transport()
            assert transport.GetType().Name == expected, (flags, str(transport.GetType()))
            assert Path(str(transport.GetType().Assembly.Location)).resolve().is_relative_to(payload)
            checked.append({"options": flags, "transport": str(transport.GetType().FullName)})
        finally:
            if transport is not None:
                transport.Dispose()
            controller.Shutdown()
    for flags in (["--serial-smoke"], ["--conformance"], ["--transport=conformance"]):
        output = io.StringIO()
        with redirect_stdout(output):
            result = cli.main(common + flags)
        assert result == 0, output.getvalue()
        if flags != ["--serial-smoke"]:
            assert "Initialization: PASS" in output.getvalue() and "Direct analog: PASS" in output.getvalue()
        assert marker.read_text() == "unchanged" and list(supplied.iterdir()) == [marker]
# Exercise the schema in the actual bundled Core assembly, using disposable copies.
from Wss.CoreModule import CoreConfig, CoreConfigController
with TemporaryDirectory(prefix="wss-address-schema-") as directory:
    address_path = Path(directory) / "stimConfig.json"
    template = json.loads((ROOT / "Config" / "stimConfig.json").read_text())
    defaults = CoreConfig()
    assert int(template["broadcastTarget"], 16) == int(defaults.broadcastTarget, 16)
    assert [int(value, 16) for value in template["wssTargets"]] == [int(value, 16) for value in defaults.wssTargets]
    for label, configuration, expected in (
        ("template", template, (0x8F, [0x81, 0x82, 0x83])),
        ("legacy", {key: value for key, value in template.items() if key not in ("broadcastTarget", "wssTargets")}, (0x8F, [0x81, 0x82, 0x83])),
        ("custom", {**template, "broadcastTarget": "0x8E", "wssTargets": ["0x80", "0x82", "0x83"]}, (0x8E, [0x80, 0x82, 0x83])),
    ):
        address_path.write_text(json.dumps(configuration))
        before = address_path.read_bytes()
        loaded = CoreConfigController(str(address_path))
        assert (int(loaded.BroadcastTarget), [int(value) for value in loaded.WssTargets]) == expected, label
        assert address_path.read_bytes() == before, label

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({"schema": "wss-cli-transport-selection/v1", "passed": True,
    "cli_file": cli.__file__, "constructed": checked, "receiver_config": "template, legacy and custom schemas passed against bundled Core; no user-file migration", "serial_smoke": "passed",
    "shared_core_conformance": "passed", "serial_auto": "configuration tested separately; construction requires a real port inventory", "physical_io": False}, indent=2))
print("PASS: real CLI transport selection, safe serial construction and shared Core conformance; no physical I/O.")
