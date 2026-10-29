"""Check public CLI selection before any device/controller initialization."""
from pathlib import Path
import unittest

from wss_cli.main import _build_parser, _config_from_args


class TransportOptionsTests(unittest.TestCase):
    def config(self, *arguments):
        return _config_from_args(_build_parser().parse_args(arguments), Path.cwd())

    def test_serial_and_existing_test_alias_remain_defaults(self):
        self.assertEqual(self.config().transport, "serial")
        self.assertEqual(self.config("--serial", "COM7").serial_port, "COM7")
        self.assertTrue(self.config("--test").test_mode)

    def test_csharp_transport_names_and_conformance_alias(self):
        self.assertTrue(self.config("--transport=test").test_mode)
        self.assertTrue(self.config("--transport=conformance").conformance_mode)
        self.assertTrue(self.config("--conformance").conformance_mode)
        self.assertTrue(self.config("--transport=BLE", "--ble-auto").ble_auto)
        self.assertIsNone(self.config("--serial=   ").serial_port)

    def test_ble_target_and_auto_reach_wrapper_configuration(self):
        named = self.config("--transport=ble", "--ble-device-name", "WSS")
        self.assertEqual((named.transport, named.ble_device_name), ("ble", "WSS"))
        self.assertEqual(self.config("--transport=ble", "--ble-device-id", "explicit-id").ble_device_id, "explicit-id")
        self.assertTrue(self.config("--transport=ble", "--ble-auto").ble_auto)

    def test_conflicting_or_incomplete_selection_fails_before_startup(self):
        for arguments in (("--transport=ble",), ("--ble-auto",),
                          ("--transport=ble", "--ble-auto", "--test"),
                          ("--transport=ble", "--ble-auto", "--serial=COM1"),
                          ("--transport=test", "--conformance"),
                          ("--transport=conformance", "--test"),
                          ("--transport=ble", "--ble-device-name=   ")):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                self.config(*arguments)
