# Standalone candidate-source CLI proof

`standalone-selected-runtime.yml` proves one explicit proposed source pair on
Windows: product CLI source `1f978246b07b033f98ea7306772508a7f0105774`, selected test source
`76680d8c0698f1a028fa214d95bd8dc6d9098bc6`, candidate wrapper source
`9c375d7d39b7fe212483112effcdcdd5b61cf381`, and guarded tooling
`dcdef289e4d2d9d54278dd8c22fb3cf76f424c7c`. This is not the
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

Tools retain literal guarded full-SHA workflow refs. The baseline helper derives
the expected tools identity from the immutable CLI product workflow. A supported
parent tooling refresh therefore requires a newly published CLI source carrying
the corresponding guarded tooling pin (without changing product source/gitlinks),
and review of this fixture tuple; never bypass the guard or exempt stale tools.
The separate selected checkout can remain frozen at its reviewed test commit.

The shared product CLI anchor is the canonical common-and-pin adoption commit A.
Both dev/main final proof workflows use that same immutable A; the selected test
checkout remains independent at its original reviewed commit. A changes no product
source or gitlink. The later B commit binds this tuple and is the final hosted proof
subject; the intermediate A commit is not an acceptance result. Ordinary main still
uses its own actual committed product/gitlink.
