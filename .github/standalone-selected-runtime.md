# Standalone candidate-source CLI proof

`standalone-selected-runtime.yml` proves one explicit proposed source pair on
Windows: product CLI source `628647e111c4b9976d28ff97e537abed0b8b0200`, selected test source
`76680d8c0698f1a028fa214d95bd8dc6d9098bc6`, candidate wrapper source
`9c375d7d39b7fe212483112effcdcdd5b61cf381`, and guarded tooling selected by
the executing workflow checkout's committed ordinary tooling binding. This is not the
ordinary product gitlink pair, authenticated Core selection, campaign evidence,
activation, or all-platform selected coverage. Ordinary native/platform gates
remain unchanged and required.

A separate job verifies the pinned authoritative producer run/artifact and whole
universal archive using the default read token. The fresh Windows executor has no
App key/token; checkouts do not persist credentials. It checks the downloaded ZIP
and candidate against direct trusted job hashes and immutable tuple constants,
validates the complete archive inventory, then executes fresh mandatory baseline
16 single-device + 16 multidevice cases. Only afterward does an isolated child
execute the ten selected CLI cases. Parent-loaded code rechecks complete baseline,
payload, product, wrapper, tools, authority and verified-input snapshots before
writing `standalone-result.json`. The all-a selection identifier is explicitly
synthetic and never submitted to Core.

Tools retain literal guarded full-SHA workflow refs. The standalone parent derives
the expected tools identity from `cli-ci.yml` in its own trusted checkout, anchored
to exact `GITHUB_SHA` (the merge commit for a pull request, not its head). It passes
that workflow source root and SHA to the baseline separately from the frozen CLI
product root and SHA. The ordinary caller still defaults to its product workflow.
A tooling refresh must preserve equality between both standalone tools checkouts
and this committed ordinary binding; never bypass the guard or exempt stale tools.
The product, selected tests, wrapper and archive remain frozen. Full workflow-source
snapshots, including `.git`, are rechecked after baseline and selected execution.
`standalone-result.json` reports `workflow_source_sha` separately from product/tools.

The shared product CLI anchor is the canonical common-and-pin adoption commit A.
Both dev/main final proof workflows use that same immutable A; the selected test
checkout remains independent at its original reviewed commit. A changes no product
source or gitlink. The later B commit binds this tuple and is the final hosted proof
subject; the intermediate A commit is not an acceptance result. Ordinary main still
uses its own actual committed product/gitlink.

Current A is `628647e111c4b9976d28ff97e537abed0b8b0200`, the immutable copy of the reviewed current dev
candidate after its approved setup-documentation correction. It includes canonical
Core `a3ce85cbecc5903d79d2e615b200f6a2cfb03741` common tooling and matching
historical Python owner pins; those are not the current tooling authority. Its entire
non-`.github` tracked tree,
including file modes and product gitlinks, is identical to previous A
`989e968903b849b0af307bf519e2daecffa2c74d`. Selected tests remain at their separate frozen source.
Retained-reference publication and full hosted B proof are separate review gates;
A alone is not an acceptance result. Main retains its different ordinary gitlink.
