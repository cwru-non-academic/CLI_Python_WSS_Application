# Python repository conformance automation

## Production path and unchanged cases

CLI validation resolves the exact `external/wss-py-wrapper` gitlink and runs the
same pinned ten-case fixture through `wss_cli.main.create_controller`, the factory
used by the normal application entry point. Python commands, ticking and Core
emulator behavior execute for real. Terminal parsing/interactive I/O are outside
this suite. The canonical case names and eighteen assertion expressions remain
unchanged, including the historical CSharp wording in fixture identities.

## Checks and evidence

`cli-ci.yml` is **CLI CI**, with acceptance **CLI general conformance**.
`wss-preflight.yml` is **WSS CLI preflight**, with the same acceptance name.
Both call the integration's reusable validation workflow. Committed mode derives
the wrapper SHA from the gitlink; candidate mode requires both exact source SHAs
and the exact verified Core producer/artifact/archive tuple. No committed DLL
fallback is used in candidate mode. Evidence includes ten actual passes, source
identities, payload/XML/log hashes, Python 3.12 and pythonnet 3.0.5 execution.

## Automatic promotion and deployment

**Promote Integration submodule** opens a gitlink-only **dev** PR after validating
the human-merged wrapper dependency PR and a fresh CLI preflight against that
actual merge. The deterministic title is **Promote universal WSS run {run_id}**.
Repeated exact requests reuse the existing PR; stale/conflicting/orphan branches
stop. Humans merge; no auto-merge, release or deployment is performed.

Publish both Python dev baselines to default main before enabling Core's separate
Python completion handoff. Existing App configuration/access is required and is
not changed here. Configured workflows, baseline copies and identical-payload
no-ops are not full propagation evidence.

See the integration's `.github/PYTHON_AUTOMATION.md` at the pinned gitlink for the
complete artifact/provenance, preflight, committed validation and merge contract.

## Manual verification and coverage limits

Hosted Windows CI covers actual Python controller construction and the ten Core
emulator cases. Terminal input/output, physical transports, GUI applications and
other runtime/platform combinations require separate verification.
