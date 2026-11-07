# HFI WSS CLI

This repository is the application/implementation repo for the HFI WSS Python CLI.

The reusable wrapper library lives in the [Python_WSS_Integration_Lib](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib) repository and is consumed here as a git submodule at `external/wss-py-wrapper/`.

## Repository Layout

- `src/wss_cli/`: app-owned CLI entry point
- `Config/`: app-owned runtime configuration JSON files
- `external/wss-py-wrapper/`: reusable wrapper library submodule

## Setup

Clone the app repo and initialize the wrapper submodule:

```bash
git clone --recursive git@github.com:cwru-non-academic/CLI_Python_WSS_Application.git
cd CLI_Python_WSS_Application
```

Create a virtual environment and install the app repo:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e external/wss-py-wrapper
python -m pip install -e .
```

The CLI can also import the wrapper directly from the checked-out submodule during editable app development, but installing the wrapper repo explicitly is the cleaner setup.

## Runtime Assets

- App-owned config location: `Config/` in this app repo
- Wrapper-owned DLL location: `external/wss-py-wrapper/Cs_Libraries/`

The CLI now constructs `WssConfig` explicitly from app-repo paths instead of relying on the old combined-repo current-working-directory layout.

## Run

```bash
wss-cli --help
wss-cli
wss-cli --test
```

Useful options:

- `--config PATH` override the config directory
- `--cs-libs PATH` override the DLL directory
- `--log-file PATH` override the log file path
- `--serial NAME` set the serial device
- `--max-retries N` set setup retries
- `--tick MS` set the tick interval
- `--transport serial|ble|test|conformance` selects the transport (case-insensitive)
- `--test` is an alias for `--transport=test`
- `--conformance` is an alias for `--transport=conformance`; it runs Core's initialization and direct-analog validators once, then exits with status 0 on success or 1 on failure
- `--serial-smoke` constructs and disposes the production serial transport with an explicit diagnostic port, without opening it
- `--ble-device-name NAME`, `--ble-device-id ID`, or `--ble-auto` explicitly selects a BLE target when using `--transport=ble`

Serial remains the default. BLE selectors cannot be combined with serial, test or
conformance options. Conformance creates a temporary calibration/configuration
fixture from shared Core scenarios; it does not edit the supplied `--config`
directory. Test mode keeps the interactive console running with Core's simulated
transport. Retry and tick defaults remain 5 and 10 ms, matching the C# CLI.

On macOS, select CoreCLR before starting the installed application, for example:

```bash
PYTHONNET_RUNTIME=coreclr wss-cli --transport=ble --ble-device-name WSS
```

The payload must include `backends/macos/WSS.Transport.BLE.MacOS.dll` and its
paired `libwss_macos_ble.dylib`. The existing wrapper loads this backend through
Core's transport factory and rejects missing files. Platform CI checks real
constructor/loading paths for all selectors on Windows, Ubuntu and macOS,
including BLE name/ID/auto selection. These checks do not scan for a device,
connect, or validate physical stimulation. Default serial auto-selection still
requires a real serial port inventory; the safe construction check uses an
explicit diagnostic port.

## Notes

- The CLI imports `WssConfig` and `StimulationController` from `wss_py_wrapper`.
- The default DLL path is `external/wss-py-wrapper/Cs_Libraries/`, which is owned by the wrapper repo.


## Device addresses and setup diagnostics

`Config/stimConfig.json` exposes Core's receiver-address settings:
`broadcastTarget` defaults to `"0x8F"`, and `wssTargets` defaults to
`["0x81", "0x82", "0x83"]` for logical Wss1, Wss2 and Wss3. These are receiver
addresses, not the host sender byte. Set the targets for your actual device
configuration (for example, an installation may need `"0x80"` for Wss1).
Existing configurations without these fields use Core's historical defaults;
these template changes do not rewrite existing user configuration. Core keeps
its existing normalization behavior for invalid address values.
Keep the firmware and calibration values appropriate to your hardware.

After changing receiver addresses, stop and restart the application so Core
constructs a new address map. The CLI `reload-core` command does not rebuild that map.
Setup continues asynchronously after controller initialization. An initialized
application or an advancing tick loop does not establish that a device is ready.
Core setup and tick errors are recorded in the configured log file; check the
reported absolute config and log paths when diagnosing connection failures.

The default config path is relative to the application's source layout, not the
current terminal directory. For a wheel installed outside an editable checkout,
pass `--config /path/to/your/Config` and `--cs-libs /path/to/Cs_Libraries`
explicitly: the wheel does not package the app-owned calibration/config files.
Startup prints these resolved paths before initialization and warns if
`stimConfig.json` is missing; Core may then create defaults, which are not a
substitute for your installation's calibrated configuration.

When the retained dependency payload is legacy and does not declare macOS BLE,
the platform probe asserts that explicit BLE selection is rejected and reports
it as unsupported. It does not count that as BLE construction or runtime proof.
A declared macOS backend missing either its managed DLL or native bridge always
fails; file absence alone never establishes legacy capability.

## CI and dependency maintenance

### Canonical conformance and platform checks

[CLI CI](.github/workflows/cli-ci.yml) resolves the exact
`external/wss-py-wrapper` gitlink and runs the pinned ten-case fixture through
`wss_cli.main.create_controller`, the production application factory. Python
commands, ticking and Core emulator behavior execute through pythonnet. The
canonical fixture keeps its historical CSharp case names and eighteen assertions.
Terminal parsing and interactive I/O are outside that suite.

[WSS CLI preflight](.github/workflows/wss-preflight.yml) delegates candidate
validation to the integration's reusable workflow. Committed CI derives the
wrapper revision from the gitlink; candidate validation requires exact wrapper
and CLI source revisions and the verified Core producer/artifact/archive tuple.
Candidate mode cannot fall back to committed DLLs. Evidence records ten actual
passes, source identities, payload/XML/log hashes, Python 3.12 and pythonnet 3.0.5.

The acceptance checks are:

- `CLI general conformance`
- `CLI platform compatibility (Windows)`
- `CLI platform compatibility (Ubuntu)`
- `CLI platform compatibility (macOS)`

The macOS check aggregates native Intel (x64) and Apple Silicon (arm64) jobs. Both must pass; their separate job names and evidence identify which architecture failed. These checks validate packaged backend loading, without a physical BLE connection.

Platform jobs build and install both wheels, exercise argument/configuration
routing into production transport construction, and check payload propagation
and managed backend selection. A declared macOS BLE payload also requires native
C ABI/export/bootstrap activation and recursive dylib retention. A legacy payload
reports BLE as unsupported; missing declared assets or skipped backend checks
cannot pass. These checks do not prove physical device communication or
stimulation. Interactive I/O, physical transports and GUI applications require
separate verification.

### Reviewed dependency promotion

[Promote Integration submodule](.github/workflows/promote-integration.yml) accepts
only a dev dispatch. It opens a gitlink-only dev PR after validating the
human-merged wrapper dependency PR and a fresh CLI preflight against that actual
merge. The deterministic title is
**Promote universal WSS run {run_id} / Integration {short_sha}**.
Repeated exact requests reuse the PR; stale, conflicting or orphan branches stop.
Humans merge; this workflow does not auto-merge or publish releases.

Versioned CLI/ROS fan-out approvals are validated by trusted integration tools.
The approval/evidence read token includes ROS for v2 proof; legacy v1 requests
retain their three-repository scope. Dispatch and publication tokens remain
CLI-only. Existing App installation access is required.

Promotion consumes the exact successful canonical Core dev-push artifact and the
accepted wrapper commit, then reruns platform preflight and ordinary PR CI.
Core PR artifacts are verification inputs, not automatic promotion evidence.
The integration's [README](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib#readme)
describes the shared artifact/provenance and merge contract; inspect the version
at the application's pinned wrapper gitlink for the matching implementation.

### Dev acceptance receipts

[Verify dev release acceptance](.github/workflows/release-receipt.yml) is a
read-only, dev-only reconciliation workflow. It accepts `producer_run_id` and
`plan_id`, downloads the unique frozen producer plan and exact ZIP, validates
policy/digests and producer gates, and requires exact current dev state.
Main/stable publication is disabled. The shared contract requires all nine
downstream targets, including MATLAB. Receipt verification creates no dependency
PRs, merges or releases.

The validator retains v2 approval, source-scope, archive checksum, strict
25/27-file projection, canonical ten-case/eighteen-assertion, platform and ROS
native checks. Applications must also prove their actual human-merged parent
and fresh merged-wrapper preflight. Original proof sources must match the frozen
target snapshot. Receipt code, normal CI and scripts must have the frozen Git
identities. Latest actual-merge push/dispatch CI must pass; synthetic PR checkout
CI cannot replace it. Core independently rechecks receipts, branches, identities,
CI, dependency pins and the emitter.

Successful preflights upload `wss-candidate-provenance` containing exactly one
six-string-field `candidate.json`, bound to canonical and projection evidence.
It is uploaded only after the existing suites pass. A preflight without this
artifact cannot establish release acceptance.

Tooling must be deployed through reviewed main and dev PRs before creating a
fresh frozen producer plan. The wrapper's closed-event fan-out reads default
main, so dev-only tooling does not update that path. A preparation merge, baseline
copy, old candidate proof or identical-payload no-op cannot substitute for the
required frozen plan and reviewed dependency acceptance. Do not substitute a
different dependency merge or replay an old closed-event run against old source.

Shared validator unit checks cover metadata binding, source/marker ambiguity,
changed/no-op state, exact checks, non-human or wrong-source merges,
latest-failed normal CI and disallowed transport writes. Full acceptance still
requires a real frozen plan, reviewed dependency merges and postmerge CI.

### Verification references

The central [verification pin reference](https://github.com/cwru-non-academic/WSS_Documentation/blob/dev/apiDocs/conceptual/verification-pin-reference.md)
explains the fixture and receiver identities as a dated inspection snapshot. It
is maintained on the documentation repository's dev branch; it is not a list of
currently deployed pins. Application setup does not require copying these values.

The reviewed [fixture configuration](.github/python-ci.json),
[normal CI](.github/workflows/cli-ci.yml),
[candidate preflight](.github/workflows/wss-preflight.yml) and
[receipt workflow](.github/workflows/release-receipt.yml) remain authoritative for
this repository's executable pins. The runtime wrapper revision is recorded by
the `external/wss-py-wrapper` Git submodule entry. Historical bootstrap and
diagnostic identities remain in their owning manifests and workflow evidence.

Candidate revisions, producer run/artifact identities, archive hashes and frozen
plan IDs bind acceptance to its actual inputs. A moving branch or unrelated
successful CI run cannot replace those inputs. The promotion title's
`{short_sha}` identifies the accepted integration revision for reviewers.

## Independent selected command tests

The trusted `.github/scripts/invoke_selected_cli_tests.py` entrypoint runs an
additional selected test bundle against explicit, unchanged CLI and wrapper
product roots and the reviewed payload. Core must authenticate the frozen test
selection first; a well-formed ID alone is not authorization.

Pass `--product-root`, `--product-sha`, `--wrapper-root`, `--wrapper-sha`,
`--payload-root`, the complete `--test-root`, `--test-sha`, `--test-repository`,
`--test-selection-id` tuple and a new `--evidence` file outside all input roots.
The selected checkout provides `conformance/test-contract.json` and named test
files only. Its product modules and release validators are not imported.

All ten production command cases must run successfully without skips. Source,
loaded module paths, actual Core assembly location and payload bytes are checked
before evidence is written. Existing mandatory wrapper, native-platform,
provenance and release gates remain required. Repository-variable workflow and
campaign evidence adoption is separate and is not activated by this entrypoint.