"""Exercise production CLI dispatch with Core-owned fixtures and wire validation.

Run explicitly with WSS_TEST_PAYLOAD pointing at a reviewed payload containing
the layered scenario API. This test never selects a physical transport.
"""
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import time
import unittest
from unittest.mock import patch

from pythonnet import load
load("coreclr")
import clr

payload = Path(os.environ["WSS_TEST_PAYLOAD"]).resolve()
clr.AddReference(str(payload / "Newtonsoft.Json.dll"))
clr.AddReference(str(payload / "WSS_Core_Interface.dll"))
from Wss.Testing import WssStimulationSequences, WssStimulationExpectation, WssStimulationWindow
from wss_cli.main import create_controller, _run_interactive_loop
from wss_py_wrapper import WssConfig


class ModeledCommandTests(unittest.TestCase):
    def test_analog_and_modeled_commands_reach_channel_two(self):
        with TemporaryDirectory(prefix="wss-cli-modeled-") as directory:
            directory = Path(directory)
            scenario = WssStimulationSequences.LayeredSingleDevice[0]
            scenario.WriteFixture(str(directory))
            controller = create_controller(WssConfig(config_path=directory,
                log_path=directory / "host.log", cs_lib_dir=payload,
                conformance_mode=True, max_setup_tries=1, tick_interval_ms=1))
            try:
                controller.Initialize()
                conformance = controller.GetConformance()
                deadline = time.monotonic() + 5
                while not controller.Started() or conformance.StimulationHistory.Count == 0:
                    self.assertLess(time.monotonic(), deadline, "CLI initialization timed out")
                    time.sleep(0.001)
                modeled = next(step for step in scenario.Steps if step.Id == "modeled.2")
                commands = iter([
                    ("analog ch2 10 10 10", WssStimulationExpectation(0x81, 2, 10, 10, 10, 0x30, True)),
                    ("stim ch2 0.5", modeled.Expectation),
                    ("quit", None),
                ])
                pending = None

                def prompt(_):
                    nonlocal pending
                    if pending is not None:
                        baseline, expectation = pending
                        deadline = time.monotonic() + 5
                        while True:
                            result = WssStimulationWindow.Evaluate(conformance, baseline, expectation, 1)
                            if result.Settled or result.Failures.Count > 0:
                                break
                            self.assertLess(time.monotonic(), deadline, str(result.Diagnostics))
                            time.sleep(0.001)
                        self.assertTrue(result.Passed, str(result.Diagnostics))
                    command, expectation = next(commands)
                    pending = (conformance.CaptureStimulationBaseline(), expectation) if expectation is not None else None
                    return command

                with patch("builtins.input", side_effect=prompt):
                    _run_interactive_loop(controller)
            finally:
                controller.Shutdown()


if __name__ == "__main__":
    unittest.main()
