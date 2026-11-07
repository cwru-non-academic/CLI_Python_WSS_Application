"""Additional real interactive-loop reload tests using the wrapper/Core emulator pattern.

Run separately from the unchanged canonical ten-case inventory with WSS_TEST_PAYLOAD
and the matching application/wrapper src on PYTHONPATH. Never uses hardware.
"""
from contextlib import redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from wss_cli.main import create_controller, _run_interactive_loop
from wss_py_wrapper import WssConfig


class CommandReloadBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wss-cli-reload-")
        self.root = Path(self.temp.name).resolve()
        self.previous_directory = Path.cwd()
        self.write_profile(self.root)
        self.config = WssConfig(config_path=self.root, log_path=self.root / "host.log",
            cs_lib_dir=Path(os.environ["WSS_TEST_PAYLOAD"]).resolve(),
            conformance_mode=True, tick_interval_ms=1, max_setup_tries=1)
        self.controller = create_controller(self.config)
        self.controller.Initialize()
        self.wait(self.controller.Started)
        # Single-token relative paths remain supported if the temporary parent has spaces.
        os.chdir(self.root)

    def tearDown(self):
        os.chdir(self.previous_directory)
        self.controller.Shutdown()
        self.temp.cleanup()

    def wait(self, condition):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.001)
        self.fail("Emulator did not observe requested state/output.")

    def commands(self, stream):
        self.console = StringIO()
        def prompt(_):
            return next(stream, "quit")
        with redirect_stdout(self.console), patch("builtins.input", side_effect=prompt):
            _run_interactive_loop(self.controller)

    def stim(self, width, amplitude):
        trace = self.controller.GetConformance()
        baseline = max(x.SequenceNumber for x in trace.MessageHistory)
        yield "stim ch2 0.5"
        self.wait(lambda: any(x.SequenceNumber > baseline and x.Channel == 2 and
            x.PulseWidth == width and x.PulseAmplitude == amplitude and
            x.InterPulseInterval == 13 for x in trace.StimulationHistory))

    def rebuilt(self, retired):
        from Wss.CoreModule import WSSMessageIDs
        self.wait(self.controller.Started)
        trace = self.controller.GetConformance()
        self.assertNotEqual(retired, trace)
        self.assertTrue(any(int(x.MessageId) == int(WSSMessageIDs.Clear) for x in trace.MessageHistory),
            "Replacement must perform real emulator setup.")
        final = [x for x in retired.StimulationHistory if x.Channel == 2][-1]
        self.assertEqual((0, 0), (final.PulseWidth, final.PulseAmplitude))

    def test_all_json_reload_updates_model_and_default_pa_without_reconnect(self):
        def stream():
            original = self.controller.GetConformance()
            self.write_profile(self.root, minimum=100, maximum=200, amplitude=4, gain=.5)
            yield "reload-params"
            self.assertEqual(original, self.controller.GetConformance())
            yield from self.stim(125, 4)
        self.commands(stream())
        self.assertNotIn("Command failed:", self.console.getvalue())

    def test_directory_file_and_defaults_route_through_actual_interactive_parser(self):
        def stream():
            yield from self.stim(100, 2)
            profile = self.root / "profile"
            self.write_profile(profile, devices=2, minimum=100, maximum=200, amplitude=4, gain=.5)
            original = self.controller.GetConformance()
            yield "reload-params profile"
            self.rebuilt(original)
            self.assertEqual(2, self.controller.GetCoreConfigCTRL().MaxWss)
            retired_count = original.MessageHistory.Count
            yield from self.stim(125, 4)
            self.assertEqual(retired_count, original.MessageHistory.Count)

            (profile / "specific.json").write_bytes((profile / "stimParams.json").read_bytes())
            directory_stack = self.controller.GetConformance()
            yield "reload-params profile/specific.json"
            self.rebuilt(directory_stack)
            self.assertEqual(1, self.controller.GetCoreConfigCTRL().MaxWss,
                "Explicit file uses startup Core, not sibling Core.")
            yield from self.stim(150, 4)
            file_stack = self.controller.GetConformance()
            os.chdir(profile)
            yield "reload-params"
            self.assertEqual(file_stack, self.controller.GetConformance())
            yield from self.stim(100, 2)

            os.chdir(self.root)
            yield "reload-params profile"
            self.wait(self.controller.Started)
            yield from self.stim(125, 4)
            before_defaults = self.controller.GetConformance()
            os.chdir(profile)
            yield "reload-params"
            self.rebuilt(before_defaults)
            self.assertEqual(1, self.controller.GetCoreConfigCTRL().MaxWss)
            yield from self.stim(100, 2)
        self.commands(stream())
        self.assertNotIn("Command failed:", self.console.getvalue())

    def test_core_only_rebuild_retains_applied_model_and_calibration_even_with_invalid_files(self):
        def stream():
            self.write_profile(self.root, minimum=100, maximum=200, amplitude=4, gain=.5)
            yield "reload-params"
            yield from self.stim(125, 4)
            (self.root / "modelConfig.json").write_text("invalid", encoding="utf-8")
            (self.root / "stimParams.json").write_text("invalid", encoding="utf-8")
            self.write_core(self.root, 2)
            for _ in range(2):
                retired = self.controller.GetConformance()
                yield "reload-core"
                self.rebuilt(retired)
                self.assertEqual(2, self.controller.GetCoreConfigCTRL().MaxWss)
                count = retired.MessageHistory.Count
                yield from self.stim(125, 4)
                self.assertEqual(count, retired.MessageHistory.Count)
            self.assertNotIn("Command failed:", self.console.getvalue())
            working = self.controller.GetConformance()
            (self.root / "stimConfig.json").write_text("invalid", encoding="utf-8")
            yield "reload-core"
            self.assertEqual(working, self.controller.GetConformance())
            self.assertEqual(2, self.controller.GetCoreConfigCTRL().MaxWss)
            self.assertEqual(1, self.console.getvalue().count("Command failed:"))
            yield from self.stim(125, 4)
        self.commands(stream())
        self.assertEqual(1, self.console.getvalue().count("Command failed:"))

    def test_inactive_core_reload_does_not_initialize_or_read_invalid_core(self):
        self.controller.Shutdown()
        self.controller = create_controller(self.config)
        def stream():
            for _ in range(2):
                (self.root / "stimConfig.json").write_text("invalid", encoding="utf-8")
                yield "reload-core"
                self.assertFalse(self.controller.Started())
                self.assertIsNone(self.controller.GetConformance())
                self.write_core(self.root, 1)
                self.controller.Initialize()
                self.wait(self.controller.Started)
                if _ == 0:
                    self.controller.Shutdown()
            # Leave a live stack for the interactive loop's existing stop/shutdown finally.
        self.commands(stream())
        self.assertNotIn("Command failed:", self.console.getvalue())

    @staticmethod
    def write_core(directory, devices):
        (directory / "stimConfig.json").write_text(json.dumps({"maxWSS": devices,
            "firmware": "J03", "useConfigAmpCurves": True, "ampCurves": [{
            "LowThreshold": 0, "LowConst": 1, "ExpPower": 1,
            "LinearOffset": -1, "LinearSlope": 1}]}), encoding="utf-8")

    @classmethod
    def write_profile(cls, directory, devices=1, minimum=50, maximum=150, amplitude=2, gain=1):
        directory.mkdir(exist_ok=True)
        cls.write_core(directory, devices)
        channels = {str(ch): {"ampMode": "PW", "minPW": minimum, "maxPW": maximum,
            "defaultPA": amplitude, "IPI": 13} for ch in range(1, 10)}
        (directory / "stimParams.json").write_text(json.dumps({"stim": {"ch": channels}}), encoding="utf-8")
        (directory / "modelConfig.json").write_text(json.dumps({"calib": {"mode": "P"},
            "constants": {"PModeProportional": gain}}), encoding="utf-8")
