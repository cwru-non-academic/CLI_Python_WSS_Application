# Inactive selected-test workflow integration

The bridge is committed but no production workflow invokes it yet. Do not activate
until reviewed current-contract Core tooling and matching immutable parent
workflow pins are adopted, compatible payload/test bundles exist, and ordinary
legacy plus candidate layered coverage is preserved on both branches. The older
Core lock already contains ci-test-selection.mjs; API presence alone does not
establish compatible adoption or trusted, isolated hosted executor integration.

The numbered recipe records the legacy online inspect/evidence and WithContext
bridge behavior, whose API compatibility is retained. It is not a deployable
offline job graph. Activation requires a separately reviewed current-contract
flow with trusted authentication and a separate credential-free hosted executor;
do not activate an unchanged fragment after readiness checks alone.

1. In the existing registered workflow prerequisite, check out the immutable Core
   revision from its verified wss-ci.lock.json with persist-credentials:false.
   Preserve literal full-SHA external reusable-workflow uses.
2. In the reviewed resolver job, declare no environment and map the fixed
   WSS_LOCAL_TEST_VARIABLES_SCHEMA=wss-effective-test-variables/v1 contract plus
   WSS_USE_PIN_TESTS, WSS_PIN_TEST_REPOSITORY and WSS_PIN_TEST_COMMIT from effective
   org/repository vars through env. These three settings are user-configurable;
   repository values override organization values. No Variables-read token is used.
3. Invoke select TARGET CANDIDATE_OR_DASH OUTPUT [committed|candidate] once.
   GH_TOKEN retains scoped read-only source/plan authority. Use actual GITHUB_*
   identity and WSS_CI_CHANNEL. Follow the reviewed Core
   tools/ci/LOCAL_TEST_VARIABLE_SNAPSHOTS.md and tools/release/CAMPAIGN_TEST_SELECTION.md:
   upload context.json only when created=true, then independently load the durable
   artifact before exposing authenticated selection outputs. Preserve v1/v2 recovery.
4. After all existing mandatory jobs succeed, run the additional selected suite
   against fresh product checkouts plus a separate selected-test checkout at those
   frozen coordinates. Keep test submodules uninitialized. The required isolated
   hosted executor receives no source/plan, App or publishing credentials,
   including read tokens. Initialize product submodules only when each one is
   independently declared in roots.products with exact repository, commit, path.
5. Write roots.json {selection_id,test_root,products:[{repository,commit,path},...]}
   using the prerequisite selection ID and exact original product SHAs. The own
   product SHA remains GITHUB_SHA. Restore authenticated context.json from the
   prerequisite artifact; set WSS_TEST_SELECTION_ID from its job output, not file.
6. Invoke the trusted WithContext bridge from the reviewed bootstrap checkout,
   not the selected test checkout. Supply exact payload/projection and a new
   external work directory. Inspect and evidence are both authenticated by Core;
   the latter runs only after the family suite succeeds and products revalidate.
7. Upload WORK/selection/evidence.json as the sole file in artifact
   wss-selected-tests-TARGET-a${github.run_attempt}. Retain detailed local suite
   evidence separately. Matrix adoption must require every selected job and every
   original mandatory platform/native gate before publishing this final artifact.

C# bridge: Invoke-SelectedCSharpTestsWithContext.ps1 -TargetId csharp-wrapper or
csharp-cli. Python CLI bridge: Invoke-SelectedPythonCliTestsWithContext.ps1.
The C# bridge takes CoreRoot, ContextPath, RootsPath, PayloadRoot, WorkRoot.
The Python CLI interface is documented below. The Core checkout
must match the checked-in reviewed lock. Current-contract adoption, immutable
bootstrap trust and isolated hosted executor integration remain prerequisites;
shared source adoption alone does not complete selected execution.
Default CI and release authorization are unchanged.
### Trusted baseline before the selected CLI child

The CLI bridge now requires explicit `Mode` and `ToolsRoot`. It executes a fresh
mandatory baseline locally, before selected code, using the immutable Python tools
pin read from the exact CLI product's committed `cli-ci.yml`. No baseline artifact,
selected test root, or selected manifest is accepted as baseline authority.

- Committed mode preserves the actual CLI wrapper gitlink and uses the ordinary
  profile runner. Modern selected tests reject a legacy profile; the separate
  ordinary legacy workflow remains unchanged.
- Candidate mode requires `FixtureRoot`, `ArtifactRoot`, and `CandidatePath` from
  the existing trusted resolver and exact fixture checkout. It uses the existing
  candidate evidence schema and does not imply acceptance of a substituted ordinary
  gitlink. The selected child uses the baseline's fresh candidate projection.
- Both canonical stages must contain all sixteen successful cases, with exact
  source, fixture, runtime, candidate, XML, log, and projection bindings. These
  canonical stages do not replace any Windows/Linux/macOS/native architecture gate.
  A future registered caller must require every existing native/platform job.
- The parent snapshots the complete baseline and payload inventory, files and empty
  directories included, plus tools and products. It separately snapshots caller
  scripts (including the Core lock), the complete Core checkout, and context/roots bytes
  immediately after trusted inspect (before baseline or selected execution). It rechecks both snapshots before invoking Core evidence after the child.
  Added, deleted, changed, or redirected paths and reparse ancestors fail closed.
- Authentication/resolution must run in a separate trusted job. The executor job
  must never receive App keys/tokens, credential-bearing action state, or bootstrap
  secrets. Environment stripping is defense in depth, not a job isolation boundary.

The selected CLI bridge no longer takes `PayloadRoot`: its payload is derived from
the freshly validated baseline. It takes `CoreRoot`, `ContextPath`, `RootsPath`,
`ToolsRoot`, `WorkRoot`, explicit `Mode`, and optional `PythonExecutable`, plus the
three candidate-only inputs above. Both work and sibling baseline paths must be new.

Snapshot and content tests use deliberately synthetic validator fixtures and real
child processes. They do not authenticate a Core context, a producer, or a campaign.
Selected execution remains inactive pending reviewed caller integration, immutable
bootstrap trust and a separate credential-free hosted executor. These changes do
not activate a production workflow.
