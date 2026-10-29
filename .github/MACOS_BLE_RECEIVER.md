# Python CLI macOS BLE receiver

This preparatory PR adds explicit `--transport=ble` routing with
`--ble-device-name`, `--ble-device-id`, or `--ble-auto`. Existing Serial defaults,
`--serial`, `--test`, stimulation commands and the shared ten-case/eighteen-assertion
Core framework remain unchanged. Conflicting/incomplete transport selections fail
before startup. The production configuration helper and controller factory are
exercised without initializing a radio in CI.

The pinned Python integration receiver supplies exact legacy/new inventory rules,
recursive dylib retention, packaged managed/native activation and provenance
validation. The four check names remain `CLI general conformance` and `CLI platform
compatibility (Windows)`, `(Ubuntu)`, `(macOS)`. Platform jobs build/install both
wheels, check real CLI argument/configuration routing into the production BLE
factory, verify payload propagation and managed backend selection, and on macOS
require C ABI/export/bootstrap activation whenever the payload declares support.
Legacy macOS payloads report unsupported BLE explicitly. Missing declared assets
or skipped new-backend validation cannot pass.

The companion wrapper receiver must be reviewed first, including its macOS-aware
C# fixture pin. This PR pins that receiver's source/tooling but does not introduce
the Core PR binary payload into the application's dependency history. A later
reviewed dependency promotion uses the exact successful canonical Core dev-push
artifact and the actual accepted wrapper commit, then reruns platform preflight
and ordinary PR CI. Core PR artifacts are local verification inputs, never
automatic-promotion proof. No merge or dispatch is performed by this preparation.

The existing pending main/dev synchronization PR is preserved. No protected branch
is reset and no dev-only promotion fix is discarded. App permissions, credentials,
rulesets and the existing CLI/ROS v2 fan-out contract are unchanged.
