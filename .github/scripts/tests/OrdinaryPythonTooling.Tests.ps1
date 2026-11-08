$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Read-OrdinaryPythonTooling.ps1"
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cli-tools-pin-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp '.github/workflows') -Force
$workflow=Join-Path $temp '.github/workflows/cli-ci.yml'
$original=Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
function Commit-Workflow([string]$Text){[IO.File]::WriteAllText($workflow,$Text);git -C $temp add . | Out-Null;git -C $temp -c user.name=Fixture -c user.email=fixture@example.invalid commit -q -m Fixture;if($LASTEXITCODE){throw 'Fixture failed'};(git -C $temp rev-parse HEAD).Trim()}
git -C $temp init -q
$sha=Commit-Workflow $original
$expected=Get-OrdinaryPythonToolsSha $temp $sha
if($expected -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact workflow source pin missing.'}
$count=1
function Reject([scriptblock]$Action){try{& $Action | Out-Null}catch{$script:count++;return};throw 'Unsafe ordinary tooling pin accepted.'}
Reject {Get-OrdinaryPythonToolsSha $temp ('f'*40)}
Reject {Assert-OrdinaryPythonToolsCheckout $temp ('f'*40)}
Add-Content $workflow ' '
Reject {Get-OrdinaryPythonToolsSha $temp $sha}
$sha=Commit-Workflow ($original.Replace("ref: $expected",'ref: main'))
Reject {Get-OrdinaryPythonToolsSha $temp $sha}
$changed=[regex]::new([regex]::Escape("ref: $expected")).Replace($original,('ref: '+('f'*40)),1)
$sha=Commit-Workflow $changed
Reject {Get-OrdinaryPythonToolsSha $temp $sha}

# The ordinary helper deliberately deduplicates matching pins and ignores other
# repositories; exact standalone inventory is a separate workflow contract.
$duplicate="`n      - uses: actions/checkout@v4`n        with:`n          repository: cwru-non-academic/Python_WSS_Integration_Lib`n          ref: $expected`n          path: tools`n"
$sha=Commit-Workflow ($original+$duplicate)
if((Get-OrdinaryPythonToolsSha $temp $sha) -cne $expected){throw 'Matching ordinary pins must deduplicate.'};$count++
$sha=Commit-Workflow ($original+$duplicate.Replace('cwru-non-academic/Python_WSS_Integration_Lib','example/wrong').Replace($expected,('f'*40)))
if((Get-OrdinaryPythonToolsSha $temp $sha) -cne $expected){throw 'Other repository pins must not set ordinary authority.'};$count++
$sha=Commit-Workflow $original
$standalone=Get-Content (Join-Path $root '.github/workflows/standalone-selected-runtime.yml') -Raw
$runner=Get-Content (Join-Path $root '.github/scripts/Invoke-StandalonePythonCliProof.ps1') -Raw
function Assert-StandaloneTooling([string]$Workflow,[string]$Runner){
    $pin=Get-OrdinaryPythonToolsSha $temp $sha
    $checkouts=@([regex]::Matches($Workflow,'(?ms)^      - uses: actions/checkout@v4\r?\n(?<body>.*?)(?=^      - |\z)'))
    $tools=@($checkouts | Where-Object {$_.Groups['body'].Value -match '(?m)^          path: tools\s*$'})
    if($tools.Count -ne 2){throw 'Standalone must contain exactly two tools checkouts.'}
    $jobs=@()
    foreach($checkout in $tools){
        $body=$checkout.Groups['body'].Value
        $repositories=@([regex]::Matches($body,'(?m)^          repository: ([^\r\n]+)\r?$'))
        $refs=@([regex]::Matches($body,'(?m)^          ref: ([^\r\n]+)\r?$'))
        if($repositories.Count -ne 1 -or $repositories[0].Groups[1].Value -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $refs.Count -ne 1 -or $refs[0].Groups[1].Value -cne $pin){throw 'Standalone tools must equal ordinary immutable repository and pin.'}
        $preceding=@([regex]::Matches($Workflow.Substring(0,$checkout.Index),'(?m)^  ([a-z-]+):\r?$'))
        $jobs+=$preceding[-1].Groups[1].Value
        if($body -notmatch '(?m)^          persist-credentials: false\s*$'){throw 'Standalone tools must not retain credentials.'}
    }
    if(($jobs -join ',') -cne 'verify-input,standalone-runtime'){throw 'Standalone tools must belong to both expected jobs.'}
    foreach($guard in @(
        '$workflowSourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ''../..''))',
        '$workflowSourceSha=$env:GITHUB_SHA',
        'Assert-PythonCliWorkflowSource $workflowSourceRoot',
        'Get-OrdinaryPythonToolsSha $workflowSourceRoot $workflowSourceSha',
        'Assert-OrdinaryPythonToolsCheckout $tools $toolsSha',
        '-WorkflowSourceRoot $workflowSourceRoot -WorkflowSourceSha $workflowSourceSha',
        '$authority=New-TrustedBaselineSnapshot @($workflowSourceRoot,$VerifiedRoot)',
        'workflow_source_sha=$workflowSourceSha'
    )){if(!$Runner.Contains($guard)){throw "Standalone authority guard missing: $guard"}}
    if(([regex]::Matches($Runner,[regex]::Escape('Assert-TrustedBaselineSnapshot $authority'))).Count -ne 2){throw 'Authority must be rechecked after baseline and selected execution.'}
}
Assert-StandaloneTooling $standalone $runner;$count++
$blocks=@([regex]::Matches($standalone,'(?ms)^      - uses: actions/checkout@v4\r?\n(?<body>.*?)(?=^      - |\z)') | Where-Object {$_.Groups['body'].Value -match '(?m)^          path: tools\s*$'})
$first=$blocks[0].Value
foreach($bad in @(
    $standalone.Replace($first,''),
    ($standalone+$first),
    $standalone.Replace($first,$first.Replace('cwru-non-academic/Python_WSS_Integration_Lib','example/wrong')),
    $standalone.Replace("ref: $expected",'ref: main'),
    $standalone.Replace($first,$first.Replace($expected,('f'*40))),
    $standalone.Replace($expected,('e'*40)),
    $standalone.Replace($first,$first.Replace('persist-credentials: false','persist-credentials: true'))
)){Reject {Assert-StandaloneTooling $bad $runner}}
foreach($guard in @(
    '$workflowSourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ''../..''))',
    '$workflowSourceSha=$env:GITHUB_SHA',
    'Assert-PythonCliWorkflowSource $workflowSourceRoot',
    'Get-OrdinaryPythonToolsSha $workflowSourceRoot $workflowSourceSha',
    'Assert-OrdinaryPythonToolsCheckout $tools $toolsSha',
    '-WorkflowSourceRoot $workflowSourceRoot -WorkflowSourceSha $workflowSourceSha',
    '$authority=New-TrustedBaselineSnapshot @($workflowSourceRoot,$VerifiedRoot)',
    'Assert-TrustedBaselineSnapshot $authority',
    'workflow_source_sha=$workflowSourceSha'
)){Reject {Assert-StandaloneTooling $standalone $runner.Replace($guard,'# omitted')}}
Reject {Assert-StandaloneTooling $standalone ([regex]::new([regex]::Escape('Assert-TrustedBaselineSnapshot $authority')).Replace($runner,'# omitted first recheck',1))}
Write-Output "PASS: $count ordinary helper and exact standalone tooling/authority contracts."

# Keep the retired frontend contract in an actual ordinary CI job, not only local tests.
function Assert-ReceiptRetirementStep([string]$Workflow) {
    $text=$Workflow.Replace("`r`n","`n")
    $job=[regex]::Match($text,'(?ms)^  prerequisites:\n(?<body>.*?)(?=^  [a-zA-Z0-9_-]+:\n|\z)').Groups['body'].Value
    $step=(@'
      - name: Verify retired receipt entrypoint contract
        shell: pwsh
        working-directory: source
        run: node --test .github/scripts/tests/ReceiptEntrypointRetirement.test.mjs
'@).Replace("`r`n","`n")+"`n"
    $node=(@'
      - uses: actions/setup-node@v4
        with:
          node-version: '24'
'@).Replace("`r`n","`n")+"`n"
    if(!$job -or $job -match '(?m)^    (if|continue-on-error):' -or !$job.Contains($step) -or [regex]::Matches($job,'(?m)^        run: node --test \.github/scripts/tests/ReceiptEntrypointRetirement\.test\.mjs$').Count -ne 1){throw 'Ordinary CI must execute the complete unconditional retired receipt test step.'}
    if($job.IndexOf($node) -lt 0 -or $job.IndexOf($node) -gt $job.IndexOf($step)){throw 'Receipt retirement contract requires Node 24 before its test step.'}
    if($job.IndexOf('      - uses: actions/checkout@v4') -lt 0 -or $job.IndexOf('      - uses: actions/checkout@v4') -gt $job.IndexOf($step)){throw 'Receipt retirement contract requires its source checkout first.'}
}
$retirementWorkflow=Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
Assert-ReceiptRetirementStep $retirementWorkflow
$retirementStep=(@'
      - name: Verify retired receipt entrypoint contract
        shell: pwsh
        working-directory: source
        run: node --test .github/scripts/tests/ReceiptEntrypointRetirement.test.mjs
'@).Replace("`r`n","`n")+"`n"
$retirementWorkflow=$retirementWorkflow.Replace("`r`n","`n")
foreach($changed in @(
    $retirementWorkflow.Replace($retirementStep,''),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('        shell: pwsh',"        if: false`n        shell: pwsh")),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('        shell: pwsh',"        continue-on-error: true`n        shell: pwsh")),
    $retirementWorkflow.Replace($retirementStep,$retirementStep.Replace('node --test','echo skipped')),
    $retirementWorkflow.Replace("node-version: '24'","node-version: '20'"),
    $retirementWorkflow.Replace("  prerequisites:`n","  prerequisites:`n    if: false`n")
)) {
    if($changed -ceq $retirementWorkflow){throw 'Retirement workflow mutation did not change its fixture.'}
    $rejected=$false;try{Assert-ReceiptRetirementStep $changed}catch{$rejected=$true}
    if(!$rejected){throw 'Disabled retirement workflow test was accepted.'}
}
Write-Output 'PASS: retired receipt hosted step and six disabling mutations.'
