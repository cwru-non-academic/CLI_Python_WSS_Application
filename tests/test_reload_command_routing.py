"""Payload-free command routing checks; runtime semantics live in conformance tests."""
from contextlib import redirect_stdout
from io import StringIO
import unittest
from unittest.mock import Mock, call, patch

from wss_cli.main import _run_interactive_loop


class ReloadCommandRoutingTests(unittest.TestCase):
    def test_default_directory_file_and_core_commands_forward_exact_arguments(self):
        controller = Mock()
        commands = ["reload-params", "reload-params profile", "reload-params profile/custom.json",
                    "reload-core", "quit"]
        with redirect_stdout(StringIO()), patch("builtins.input", side_effect=commands):
            _run_interactive_loop(controller)
        self.assertEqual(controller.method_calls, [call.LoadParamsJson(), call.LoadParamsJson("profile"),
            call.LoadParamsJson("profile/custom.json"), call.LoadCoreConfigFile(),
            call.StopStimulation(), call.Shutdown()])

    def test_failed_reload_is_reported_and_next_command_still_reaches_controller(self):
        controller = Mock()
        controller.LoadCoreConfigFile.side_effect = ValueError("invalid Core fixture")
        console = StringIO()
        with redirect_stdout(console), patch("builtins.input", side_effect=["reload-core", "reload-params", "quit"]):
            _run_interactive_loop(controller)
        self.assertIn("Command failed: invalid Core fixture", console.getvalue())
        self.assertEqual(controller.method_calls, [call.LoadCoreConfigFile(), call.LoadParamsJson(),
            call.StopStimulation(), call.Shutdown()])
