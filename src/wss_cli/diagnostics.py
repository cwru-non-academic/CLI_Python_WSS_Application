"""Hardware-free CLI diagnostics using the production wrapper and Core evaluators."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path


def create_conformance_config(cs_lib_dir: Path, destination: Path) -> None:
    """Write an isolated fixture using Core's shared scenario values."""
    from wss_py_wrapper.wss_loader import WssLoader, collect_dlls

    dlls = collect_dlls(cs_lib_dir)
    if not any(p.name == "WSS_Core_Interface.dll" for p in dlls):
        raise FileNotFoundError(f"WSS_Core_Interface.dll is missing from {cs_lib_dir}")
    WssLoader(dlls).load()
    from Wss.Testing import WssBehaviorScenarios

    fixture = WssBehaviorScenarios.StimulationFixture
    channel = str(int(WssBehaviorScenarios.DirectAnalog.Channel))
    stimulation = {
        "maxWSS": 1, "firmware": "J03", "broadcastTarget": "0x8F",
        "wssTargets": ["0x81", "0x82", "0x83"], "useConfigAmpCurves": True,
        "ampCurves": [{
            "LowThreshold": float(fixture.CurveLowThreshold),
            "LowConst": float(fixture.CurveLowConstant),
            "ExpPower": float(fixture.CurveExponent),
            "LinearOffset": float(fixture.CurveLinearOffset),
            "LinearSlope": float(fixture.CurveLinearSlope),
        }],
    }
    parameters = {"stim": {"ch": {channel: {
        "ampMode": str(fixture.AmplitudeMode),
        "minPW": int(fixture.MinimumPulseWidth),
        "maxPW": int(fixture.MaximumPulseWidth),
        "minPA": 0.0, "maxPA": 0.0,
        "defaultPA": float(fixture.DefaultAmplitudeMa),
        "defaultPW": 50, "IPI": int(fixture.InterPulseInterval),
    }}}}
    (destination / "stimConfig.json").write_text(json.dumps(stimulation), encoding="utf-8")
    (destination / "stimParams.json").write_text(json.dumps(parameters), encoding="utf-8")


def _failure(check: str, failures) -> int:
    print(f"{check}: FAIL", file=sys.stderr)
    for failure in failures:
        print(str(failure), file=sys.stderr)
    print("Result: FAIL", file=sys.stderr)
    return 1


def run_conformance(controller) -> int:
    """Evaluate Core's initialization and direct-analog scenarios without devices."""
    from Wss.Testing import WssBehaviorScenarios

    print("WSS conformance:")
    conformance = controller.GetConformance()
    if conformance is None:
        return _failure("Initialization", ["The controller did not expose Core's evaluator."])
    scenario = WssBehaviorScenarios.Initialization
    operational = stream = False
    for _ in range(3000):
        operational = operational or controller.Started()
        stream = stream or conformance.StimulationHistory.Count > 0
        if ((not scenario.RequiresOperationalState or operational)
                and (not scenario.RequiresStreamObservation or stream)):
            break
        time.sleep(0.001)
    if scenario.RequiresOperationalState and not operational:
        return _failure("Initialization", ["Core did not reach operational state within the finite poll limit."])
    if scenario.RequiresStreamObservation and not stream:
        return _failure("Initialization", ["Core did not emit a startup stream within the finite poll limit."])
    result = conformance.ValidateInitialization()
    if not result.Passed:
        return _failure("Initialization", result.Failures)
    print("Initialization: PASS")
    analog = WssBehaviorScenarios.DirectAnalog
    amplitude = int(analog.AmplitudeMa)
    if amplitude != analog.AmplitudeMa:
        return _failure("Direct analog", ["The shared amplitude is not supported by the integer CLI API."])
    baseline = conformance.CaptureStimulationBaseline()
    controller.StimulateAnalog(f"ch{int(analog.Channel)}", int(analog.PulseWidth), amplitude, int(analog.InterPulseInterval))
    result = conformance.ValidateStimulation(analog.Expectation, baseline)
    for _ in range(2000):
        if result.Passed:
            break
        time.sleep(0.001)
        result = conformance.ValidateStimulation(analog.Expectation, baseline)
    if not result.Passed:
        return _failure("Direct analog", result.Failures)
    print("Direct analog: PASS")
    print("Result: PASS")
    return 0
