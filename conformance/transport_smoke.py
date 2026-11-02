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


def legacy_macos_payload(payload: Path) -> bool:
    """Read the loaded facade capability; missing files cannot imply legacy."""
    import clr
    from System import Array, Object, ArgumentOutOfRangeException
    from System.Reflection import BindingFlags, TargetInvocationException
    from Wss.Transports import BleNusTransport

    loader = clr.GetClrType(BleNusTransport).Assembly.GetType(
        "Wss.Transports.Backends.BleBackendLoader", True)
    identity = loader.GetMethod("GetBackendIdentity", BindingFlags.NonPublic | BindingFlags.Static)
    if identity is None:
        raise RuntimeError("Unknown BLE capability contract")
    declared = True
    try:
        mapping = identity.Invoke(None, Array[Object](["macos"]))
        assert str(mapping.Item1) == "WSS.Transport.BLE.MacOS"
        assert str(mapping.Item2) == "Wss.Transports.Backends.MacOS.MacBleNusBackendFactory"
    except TargetInvocationException as error:
        if not isinstance(error.InnerException, ArgumentOutOfRangeException) or error.InnerException.ParamName != "platform":
            raise
        declared = False
    directory = payload / "backends" / "macos"
    files = {str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file()} if directory.exists() else set()
    expected = {"WSS.Transport.BLE.MacOS.dll", "libwss_macos_ble.dylib"} if declared else set()
    if files != expected:
        raise RuntimeError("Declared macOS BLE assets are missing, or legacy payload carries orphan assets")
    return not declared

parser = argparse.ArgumentParser()
parser.add_argument("--payload", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
payload = args.payload.resolve()
checked = []
unsupported = []
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
            legacy = legacy_macos_payload(payload)
            if sys.platform == "darwin" and expected == "BleNusTransport" and legacy:
                try:
                    transport = controller._create_transport()
                except FileNotFoundError:
                    unsupported.append({"selection": flags, "reason": "legacy facade does not declare macOS BLE; explicit selection rejected"})
                    print("UNSUPPORTED: legacy macOS BLE selection explicitly rejected; no BLE runtime support claimed.")
                    continue
                raise AssertionError("Legacy macOS BLE must reject explicit selection")
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
# A missing declared backend must fail, never become legacy/unsupported success.
with TemporaryDirectory(prefix="wss-ble-capability-negative-") as directory:
    negative = Path(directory)
    legacy = legacy_macos_payload(payload)
    if legacy:
        assert legacy_macos_payload(negative)
        orphan = negative / "backends/macos/WSS.Transport.BLE.MacOS.dll"
        orphan.parent.mkdir(parents=True)
        orphan.write_bytes(b"negative fixture, not a release asset")
    try:
        legacy_macos_payload(negative)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Missing declared or orphan legacy macOS assets must fail")

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
    "cli_file": cli.__file__, "constructed": checked, "unsupported": unsupported, "capability_rejection": "passed against loaded facade mapping", "receiver_config": "template, legacy and custom schemas passed against bundled Core; no user-file migration", "serial_smoke": "passed",
    "shared_core_conformance": "passed", "serial_auto": "configuration tested separately; construction requires a real port inventory", "physical_io": False}, indent=2))
print("PASS: real CLI transport selection, safe serial construction and shared Core conformance; no physical I/O.")
