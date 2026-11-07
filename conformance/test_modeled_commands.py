"""Production CLI command matrix using Core-owned fixtures and wire validation.

Requires WSS_TEST_PAYLOAD to select an exact reviewed payload. Emulator only.
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
from Wss.Testing import WssStimulationSequences, WssStimulationWindow
from wss_cli.main import create_controller, _run_interactive_loop
from wss_py_wrapper import WssConfig

scenarios = list(WssStimulationSequences.LayeredSingleDevice) + list(WssStimulationSequences.LayeredMultipleDevices)
scenarios += [s for s in list(WssStimulationSequences.SingleDevice) + list(WssStimulationSequences.MultipleDevices) if s.Id.startswith("analog.")]
required = {f"modeled.{model}.{mode}.{stage}" for model in ("p", "pd") for mode in ("pw", "pa") for stage in ("single", "multi")}
required |= {"analog.multichannel-isolation", "analog.multidevice-isolation"}
assert len(scenarios) == 10 and {s.Id for s in scenarios} == required, "Incomplete command scenario inventory"


class ModeledCommandTests(unittest.TestCase):
    def run_scenario(self, scenario):
        with TemporaryDirectory(prefix="wss-cli-modeled-") as directory:
            directory = Path(directory)
            scenario.WriteFixture(str(directory))
            controller = create_controller(WssConfig(config_path=directory,
                log_path=directory / "host.log", cs_lib_dir=payload,
                conformance_mode=True, max_setup_tries=1, tick_interval_ms=1))
            try:
                controller.Initialize()
                conformance = controller.GetConformance()
                deadline = time.monotonic() + 5
                while not controller.Started() or not all(any(f.Target == 0x81 + unit for f in conformance.StimulationHistory) for unit in range(scenario.DeviceCount)):
                    self.assertLess(time.monotonic(), deadline, "CLI initialization timed out")
                    time.sleep(0.001)
                aliases = ["thumb", "index", "middle", "ring", "pinky"]

                def commands():
                    for step in scenario.Steps:
                        step.PrepareReload(str(directory))
                        if step.ReloadParameters:
                            yield "reload-params", None
                        # No model-only reload command exists in the current CLI.
                        if step.ReloadModel:
                            controller.GetModelConfigCTRL().LoadModelJson()
                        channel = aliases[step.GlobalChannel - 1] if scenario.ModelMode == "P" and step.GlobalChannel <= len(aliases) else f"ch{step.GlobalChannel}"
                        expected = step.Expectation
                        command = f"stim {channel} {step.Input}" if step.Modeled else f"analog {channel} {expected.PulseWidth} {expected.PulseAmplitude} {expected.InterPulseInterval}"
                        yield command, expected
                    yield "quit", None

                stream = commands()
                pending = None
                def prompt(_):
                    nonlocal pending
                    if pending is not None:
                        baseline, expectation = pending
                        deadline = time.monotonic() + 5
                        while True:
                            result = WssStimulationWindow.Evaluate(conformance, baseline, expectation, scenario.DeviceCount)
                            if result.Settled or result.Failures.Count > 0:
                                break
                            self.assertLess(time.monotonic(), deadline, str(result.Diagnostics))
                            time.sleep(0.001)
                        self.assertTrue(result.Passed, str(result.Diagnostics))
                    command, expectation = next(stream)
                    pending = (conformance.CaptureStimulationBaseline(), expectation) if expectation is not None else None
                    return command
                with patch("builtins.input", side_effect=prompt):
                    _run_interactive_loop(controller)
            finally:
                controller.Shutdown()


for scenario in scenarios:
    def case(self, scenario=scenario):
        self.run_scenario(scenario)
    setattr(ModeledCommandTests, "test_" + scenario.Id.replace(".", "_"), case)

if __name__ == "__main__":
    unittest.main()
