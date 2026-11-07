param([Parameter(Mandatory)][string]$ToolsRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../TrustedPythonCliBaseline.ps1"
. (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
$config=Read-PythonConfig (Join-Path $ToolsRoot '.github/python-ci.json')
$base=Join-Path ([IO.Path]::GetTempPath()) ('cli-baseline-content-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $base
$wrapper=[IO.Path]::GetFullPath($ToolsRoot)
$wrapperSha='a'*40;$cliSha='b'*40
$candidate=[pscustomobject]@{repository='cwru-non-academic/WSSCore';commit=('c'*40);run_id='1';artifact_id='2';archive='WSS-Universal-ci.zip';sha256=('d'*64)}
# Synthetic bytes test the validators only. They are NOT runtime/producer evidence.
function New-Fixture([string]$Root){
    $payload=Join-Path $Root 'payload'
    $null=New-Item -ItemType Directory -Path $payload -Force
    $files=@(foreach($name in Get-WssUniversalFiles 'macos-ble-v1'){
        $file=Join-Path $payload $name
        $null=New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force
        [IO.File]::WriteAllText($file,'synthetic validator fixture')
        @{source=$name;sha256=(Get-FileHash $file).Hash.ToLowerInvariant()}
    })
    $projection=@{schema='wss-python-projection/v1';universal_contract='macos-ble-v1';candidate=$candidate;files=$files;projection_sha256=(Get-PythonProjectionDigest $files)}
    foreach($stage in @('single','multi')){
        $directory=if($stage -ceq 'single'){$Root}else{Join-Path $Root 'multi'}
        $null=New-Item -ItemType Directory -Path $directory -Force
        $names=if($stage -ceq 'single'){@($config.dotnet_expected_cases)}else{@($config.dotnet_expected_cases | Select-Object -First 10)+@($config.multidevice_expected_cases)}
        $cases=($names | ForEach-Object {'<test-case name="'+[Security.SecurityElement]::Escape($_)+'" result="Passed" />'}) -join ''
        $xml='<test-run result="Passed" testcasecount="16" total="16" passed="16" failed="0" skipped="0" inconclusive="0">'+$cases+'</test-run>'
        [IO.File]::WriteAllText((Join-Path $directory 'results.xml'),$xml)
        [IO.File]::WriteAllText((Join-Path $directory 'dotnet.log'),'synthetic passing log')
        $projection | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $directory 'projection.json')
        @{
            schema='wss-python-evidence/v1';mode='candidate';role='cli';execution='pythonnet';python_executed=$true
            wrapper_sha=$wrapperSha;cli_sha=$cliSha;test_root=$wrapper;test_sha=$wrapperSha
            test_repository='cwru-non-academic/Python_WSS_Integration_Lib';test_selection_id='';test_contract_sha256=''
            stage=$stage;discovered=16;executed=16;passed=16;failed=0;skipped=0;assertion_expressions=20
            sdk=$config.dotnet_sdk;python=$config.python_version;pythonnet=$config.pythonnet_version;target_framework='net9.0';test_framework='NUnit 3.14.0'
            run_repository=$env:GITHUB_REPOSITORY;run_id=$env:GITHUB_RUN_ID;run_sha=$env:GITHUB_SHA
            candidate=$candidate;projection_sha256=$projection.projection_sha256
            fixture_sha=$config.fixture_commit;fixture_sha256=$config.fixture_sha256
            results_sha256=(Get-FileHash (Join-Path $directory 'results.xml')).Hash.ToLowerInvariant()
            log_sha256=(Get-FileHash (Join-Path $directory 'dotnet.log')).Hash.ToLowerInvariant()
        } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $directory 'evidence.json')
    }
}
$cases=@('positive','source','run','mode','schema','count','multi-count','selected-source','hash','payload','missing','xml','projection')
foreach($case in $cases){
    $root=Join-Path $base $case
    New-Fixture $root
    $ep=Join-Path $root 'evidence.json';$e=Get-Content $ep -Raw | ConvertFrom-Json
    switch($case){
        'source' {$e.cli_sha='e'*40}
        'run' {$e.run_id='wrong-run'}
        'mode' {$e.mode='committed'}
        'schema' {$e.schema='wss-python-profile-evidence/v1'}
        'count' {$e.executed=15}
        'selected-source' {$e.test_selection_id='f'*64;$e.test_contract_sha256='e'*64}
        'hash' {$e.log_sha256='0'*64}
        'multi-count' {
            $mp=Join-Path $root 'multi/evidence.json';$m=Get-Content $mp -Raw | ConvertFrom-Json
            $m.passed=15;$m | ConvertTo-Json -Depth 8 | Set-Content $mp
        }
        'payload' {[IO.File]::WriteAllText((Join-Path $root 'payload/WSS_Core_Interface.dll'),'changed')}
        'missing' {Remove-Item -LiteralPath (Join-Path $root 'multi/results.xml')}
        'xml' {
            $xp=Join-Path $root 'results.xml'
            $xml=(Get-Content $xp -Raw).Replace('result="Passed"','result="Skipped"')
            [IO.File]::WriteAllText($xp,$xml);$e.results_sha256=(Get-FileHash $xp).Hash.ToLowerInvariant()
        }
        'projection' {$e.projection_sha256='0'*64}
    }
    $e | ConvertTo-Json -Depth 8 | Set-Content $ep
    $rejected=$false
    try {Assert-PythonCliBaselineContent $root (Join-Path $root 'payload') $wrapper $wrapperSha $cliSha candidate $config $candidate}
    catch {$rejected=$true;if($case -ceq 'positive'){throw}}
    if(($case -ceq 'positive' -and $rejected) -or ($case -cne 'positive' -and !$rejected)){throw "Content regression: $case"}
    Write-Host "PASS: baseline content $case"
}

# Real entry-point plumbing with synthetic repositories and nonloading children.
# Synthetic tool functions replace runtime validators/children only. Git authority,
# tools guards and full .git-inclusive snapshots remain the actual implementations.
$physicalTemp=(& python -c 'import os,tempfile; print(os.path.realpath(tempfile.gettempdir()))').Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot resolve physical temporary directory.'}
$plumbing=Join-Path $physicalTemp ('cli-baseline-plumbing-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $plumbing
function Write-PlumbingFile([string]$Path,[string]$Text){
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path,$Text)
}
function Commit-PlumbingRepo([string]$Root){
    git -C $Root add . | Out-Null
    git -C $Root -c user.name=Fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m 'Synthetic authority fixture'
    if($LASTEXITCODE){throw 'Synthetic fixture commit failed.'}
    (git -C $Root rev-parse HEAD).Trim()
}
function New-PlumbingRepo([string]$Name,[string]$Repository='CLI_Python_WSS_Application'){
    $path=Join-Path $plumbing $Name
    $null=New-Item -ItemType Directory -Path $path
    git -C $path init -q
    git -C $path remote add origin "https://github.com/cwru-non-academic/$Repository.git"
    if($LASTEXITCODE){throw 'Synthetic fixture init failed.'}
    $path
}
$mockTools=New-PlumbingRepo 'tools' 'Python_WSS_Integration_Lib'
$mockContract=@'
function Assert-PythonSource([string]$Root,[string]$Sha,[switch]$IgnoreSubmodule){
    $global:CliBaselinePlumbing.sources+=,@($Root,$Sha)
}
function Read-PythonConfig([string]$Path){[pscustomobject]@{fixture_commit=('c'*40)}}
function Assert-PythonCandidate($Candidate){}
function Assert-PythonCliBaselineContent {$global:CliBaselinePlumbing.validated++}
function Invoke-CredentialFreeSelectedPowerShell([string]$Runner,[hashtable]$Options){
    $global:CliBaselinePlumbing.children++
    $global:CliBaselinePlumbing.options=$Options.Clone()
    $global:CliBaselinePlumbing.optionalLocks=$env:GIT_OPTIONAL_LOCKS
    if($Options.Stage -cne 'all' -or $Options.Role -cne 'cli'){throw 'Wrong baseline child stage/role.'}
    if($Options.ContainsKey('WorkflowSourceRoot') -or $Options.ContainsKey('WorkflowSourceSha')){throw 'Authority leaked into execution options.'}
    $null=New-Item -ItemType Directory -Path (Join-Path $Options.OutputRoot 'projection') -Force
    if($global:CliBaselinePlumbing.baselineMutation){
        [IO.File]::AppendAllText($global:CliBaselinePlumbing.baselineMutation,'synthetic child mutation')
    }
}
function Invoke-CredentialFreeSelectedProcess([string]$FilePath,[string[]]$Arguments){
    $global:CliBaselinePlumbing.selected++
    $index=[Array]::IndexOf($Arguments,'--evidence')
    if($index -lt 0){throw 'Selected evidence argument missing.'}
    $path=$Arguments[$index+1]
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    [IO.File]::WriteAllText($path,'{"tests_run":10,"passed":true}')
    if($global:CliBaselinePlumbing.selectedMutation){
        [IO.File]::AppendAllText($global:CliBaselinePlumbing.selectedMutation,'synthetic selected mutation')
    }
}
function Get-WssUniversalFiles($Contract){@('synthetic.txt')}
function Get-WssUniversalArchiveHashes {param($Archive,$ExpectedSha256,$ExpectedFiles)}
'@
Write-PlumbingFile (Join-Path $mockTools '.github/scripts/PythonContract.ps1') $mockContract
Write-PlumbingFile (Join-Path $mockTools '.github/scripts/PythonProfiles/Contract.ps1') '# Synthetic nonloading candidate-mode fixture.'
Write-PlumbingFile (Join-Path $mockTools '.github/scripts/wss-ci/Assert-UniversalArchive.ps1') '# Archive shape is outside these plumbing tests.'
$mockToolsSha=Commit-PlumbingRepo $mockTools
$workflowText="steps:"+[Environment]::NewLine+"  - uses: actions/checkout@v4"+[Environment]::NewLine+"    with:"+[Environment]::NewLine+"      repository: cwru-non-academic/Python_WSS_Integration_Lib"+[Environment]::NewLine+"      ref: $mockToolsSha"+[Environment]::NewLine+"      path: tools"+[Environment]::NewLine
$authority=New-PlumbingRepo 'authority'
Write-PlumbingFile (Join-Path $authority '.github/workflows/cli-ci.yml') $workflowText
$null=New-Item -ItemType Directory -Path (Join-Path $authority '.github/scripts')
foreach($name in @('Invoke-StandalonePythonCliProof.ps1','TrustedPythonCliBaseline.ps1','Read-OrdinaryPythonTooling.ps1','TrustedBaseline.ps1','SelectedProcessIsolation.ps1')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../$name") -Destination (Join-Path $authority ".github/scripts/$name")
}
$authoritySha=Commit-PlumbingRepo $authority
$product=New-PlumbingRepo 'product'
Write-PlumbingFile (Join-Path $product '.github/workflows/cli-ci.yml') ($workflowText.Replace($mockToolsSha,('d'*40)))
$productSha=Commit-PlumbingRepo $product
if((Get-OrdinaryPythonToolsSha $product $productSha) -ceq $mockToolsSha){throw 'Fixture must distinguish historical product from current workflow authority.'}
$mockWrapper=Join-Path $plumbing 'wrapper'
Write-PlumbingFile (Join-Path $mockWrapper '.github/python-ci.json') '{}'
Write-PlumbingFile (Join-Path $mockWrapper 'conformance/synthetic.txt') 'nonloading fixture'
$mockFixture=Join-Path $plumbing 'fixture';$mockArtifact=Join-Path $plumbing 'artifact'
$null=New-Item -ItemType Directory -Path $mockFixture,$mockArtifact
$mockCandidate=Join-Path $plumbing 'candidate.json'
Write-PlumbingFile $mockCandidate '{}'
function Reset-PlumbingState {
    $global:CliBaselinePlumbing=@{children=0;selected=0;validated=0;sources=@();options=$null;baselineMutation='';selectedMutation=''}
}
function Invoke-PlumbingCase([string]$Name,[hashtable]$Overrides=@{},[switch]$Ordinary){
    $options=@{ToolsRoot=$mockTools;WrapperRoot=$mockWrapper;WrapperSha=('b'*40);CliRoot=$product;CliSha=$productSha;
        OutputRoot=(Join-Path $plumbing ('output-'+$Name));Mode='candidate';FixtureRoot=$mockFixture;ArtifactRoot=$mockArtifact;CandidatePath=$mockCandidate}
    if(!$Ordinary){$options.WorkflowSourceRoot=$authority;$options.WorkflowSourceSha=$authoritySha}
    foreach($key in $Overrides.Keys){$options[$key]=$Overrides[$key]}
    Invoke-TrustedPythonCliBaseline @options
}
function Reject-Plumbing([string]$Name,[scriptblock]$Action,[string]$Message,[int]$Children=0,[int]$Selected=0){
    Reset-PlumbingState
    $caught=$null
    try{& $Action | Out-Null}catch{$caught=$_}
    if(!$caught -or $caught.Exception.Message -notmatch $Message){throw "Plumbing case $Name did not reject for the expected reason: $caught"}
    if($global:CliBaselinePlumbing.children -ne $Children -or $global:CliBaselinePlumbing.selected -ne $Selected){throw "Plumbing case $Name reached unexpected execution phases."}
    Write-Host "PASS: baseline plumbing $Name"
}
Reset-PlumbingState
$savedLocks=[Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
try {
    $env:GIT_OPTIONAL_LOCKS='1'
    $result=Invoke-PlumbingCase 'separate'
    if($env:GIT_OPTIONAL_LOCKS -cne '1' -or $global:CliBaselinePlumbing.optionalLocks -cne '1'){throw 'Trusted reads changed child/caller Git lock environment.'}
} finally {[Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS',$savedLocks)}
if($result.tools_sha -cne $mockToolsSha -or $result.workflow_source_sha -cne $authoritySha -or
   $global:CliBaselinePlumbing.children -ne 1 -or $global:CliBaselinePlumbing.validated -ne 1 -or
   $global:CliBaselinePlumbing.options.CliRoot -cne $product -or $global:CliBaselinePlumbing.options.CliSha -cne $productSha){throw 'Separate authority/product plumbing mismatch.'}
Write-Host 'PASS: baseline plumbing separate authority and product'
Reset-PlumbingState
$result=Invoke-PlumbingCase 'ordinary' @{CliRoot=$authority;CliSha=$authoritySha} -Ordinary
if($result.workflow_source_sha -cne $authoritySha -or $global:CliBaselinePlumbing.children -ne 1){throw 'Ordinary default authority failed.'}
Write-Host 'PASS: baseline plumbing ordinary defaults'
Reject-Plumbing 'partial-root' {Invoke-PlumbingCase 'partial-root' @{WorkflowSourceRoot=$authority} -Ordinary} 'workflow|authority|together|pair'
Reject-Plumbing 'partial-sha' {Invoke-PlumbingCase 'partial-sha' @{WorkflowSourceSha=$authoritySha} -Ordinary} 'workflow|authority|together|pair'
Reject-Plumbing 'blank-root' {Invoke-PlumbingCase 'blank-root' @{WorkflowSourceRoot=''}} 'workflow|authority|blank|empty'
Reject-Plumbing 'blank-sha' {Invoke-PlumbingCase 'blank-sha' @{WorkflowSourceSha=''}} 'workflow|authority|blank|empty'
Reject-Plumbing 'blank-pair' {Invoke-PlumbingCase 'blank-pair' @{WorkflowSourceRoot='';WorkflowSourceSha=''}} 'workflow|authority|blank|empty'
Reject-Plumbing 'wrong-authority-sha' {Invoke-PlumbingCase 'wrong-authority-sha' @{WorkflowSourceSha=('f'*40)}} 'workflow source|authority'
$authorityWorkflow=Join-Path $authority '.github/workflows/cli-ci.yml'
[IO.File]::AppendAllText($authorityWorkflow,'dirty')
Reject-Plumbing 'dirty-authority' {Invoke-PlumbingCase 'dirty-authority'} 'clean|dirty|executable inputs'
[IO.File]::WriteAllText($authorityWorkflow,$workflowText)
Reject-Plumbing 'wrong-tools' {Invoke-PlumbingCase 'wrong-tools' @{ToolsRoot=$product}} 'Tools checkout differs'
$toolFile=Join-Path $mockTools '.github/scripts/PythonContract.ps1'
[IO.File]::AppendAllText($toolFile,'dirty')
Reject-Plumbing 'dirty-tools' {Invoke-PlumbingCase 'dirty-tools'} 'clean|dirty'
[IO.File]::WriteAllText($toolFile,$mockContract)

git -C $authority remote set-url origin https://github.com/cwru-non-academic/Wrong_Application.git
Reject-Plumbing 'wrong-authority-origin' {Invoke-PlumbingCase 'wrong-authority-origin'} 'workflow authority repository'
git -C $authority remote set-url origin https://github.com/cwru-non-academic/CLI_Python_WSS_Application.git
git -C $mockTools remote set-url origin https://github.com/cwru-non-academic/Wrong_Tools.git
Reject-Plumbing 'wrong-tools-origin' {Invoke-PlumbingCase 'wrong-tools-origin'} 'trusted tooling repository'
git -C $mockTools remote set-url origin https://github.com/cwru-non-academic/Python_WSS_Integration_Lib.git
foreach($flag in @('assume-unchanged','skip-worktree')){
    git -C $authority update-index "--$flag" -- .github/workflows/cli-ci.yml
    Reject-Plumbing ('authority-'+$flag) {Invoke-PlumbingCase ('authority-'+$flag)} 'Git index'
    git -C $authority update-index "--no-$flag" -- .github/workflows/cli-ci.yml
    git -C $mockTools update-index "--$flag" -- .github/scripts/PythonContract.ps1
    Reject-Plumbing ('tools-'+$flag) {Invoke-PlumbingCase ('tools-'+$flag)} 'Git index'
    git -C $mockTools update-index "--no-$flag" -- .github/scripts/PythonContract.ps1
}
foreach($source in @($authority,$mockTools)){
    $exclude=Join-Path $source '.git/info/exclude'
    $savedExclude=[IO.File]::ReadAllBytes($exclude)
    [IO.File]::AppendAllText($exclude,([Environment]::NewLine+'.github/ignored.ps1'+[Environment]::NewLine))
    $ignored=Join-Path $source '.github/ignored.ps1'
    [IO.File]::WriteAllText($ignored,'# synthetic ignored executable input')
    Reject-Plumbing ('ignored-input-'+(Split-Path $source -Leaf)) {Invoke-PlumbingCase ('ignored-'+[guid]::NewGuid().ToString('N'))} 'ignored or untracked executable inputs'
    Remove-Item -LiteralPath $ignored
    [IO.File]::WriteAllBytes($exclude,$savedExclude)
}

Reject-Plumbing 'authority-output-overlap' {Invoke-PlumbingCase 'authority-output-overlap' @{OutputRoot=(Join-Path $authority 'new-output')}} 'overlap'
foreach($mutation in @('.github/workflows/cli-ci.yml','.git/config')){
    $path=Join-Path $authority $mutation;$saved=[IO.File]::ReadAllBytes($path)
    Reject-Plumbing ('child-mutation-'+$mutation) { $global:CliBaselinePlumbing.baselineMutation=$path;Invoke-PlumbingCase ('mutate-'+[guid]::NewGuid().ToString('N')) } 'inventory/content' -Children 1
    [IO.File]::WriteAllBytes($path,$saved)
}
# Run the actual standalone parent against the synthetic committed authority root.
# Mock archive hashing/extraction and product fixture identities, never load a DLL.
$standalone=Join-Path $authority '.github/scripts/Invoke-StandalonePythonCliProof.ps1'
$verified=Join-Path $plumbing 'verified'
$archive=Join-Path $verified 'downloads/WSS-Universal-ci.zip'
Write-PlumbingFile $archive 'synthetic archive bytes, never loaded'
$archiveHash='e6256d26b833f27f5b1ad11af4dfdcce03603020dc5c346b7c1e9b4b61ed927f'
$standaloneCandidate=Join-Path $verified 'candidate.json'
Write-PlumbingFile $standaloneCandidate ('{"repository":"cwru-non-academic/WSSCore","commit":"0bc9e2d0af507ee729d39d3a30ab005cc136eabf","run_id":"42288988734","artifact_id":"13538204103","archive":"WSS-Universal-ci.zip","sha256":"'+$archiveHash+'"}')
$candidateHash=(Get-FileHash -LiteralPath $standaloneCandidate).Hash.ToLowerInvariant()
$null=New-Item -ItemType Directory -Path (Join-Path $plumbing 'cli'),(Join-Path $plumbing 'selected-tests')
$standaloneOptions=@{Workspace=$plumbing;VerifiedRoot=$verified;ExpectedArchiveHash=$archiveHash;ExpectedCandidateHash=$candidateHash;ExpectedArchiveContract='macos-ble-v1'}
function Get-FileHash {
    param([Parameter(Position=0)][string]$Path,[string]$LiteralPath,[string]$Algorithm='SHA256')
    $target=if($LiteralPath){$LiteralPath}else{$Path}
    if($target -ceq $archive){return [pscustomobject]@{Hash=$archiveHash;Path=$target}}
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $target -Algorithm $Algorithm
}
function Expand-Archive {param($LiteralPath,$DestinationPath);$null=New-Item -ItemType Directory -Path (Join-Path $DestinationPath 'WSS-Universal') -Force}
$savedGithubSha=$env:GITHUB_SHA
try{
    $env:GITHUB_SHA=''
    Reject-Plumbing 'standalone-missing-parent-sha' {& $standalone @standaloneOptions -OutputRoot (Join-Path $plumbing 'standalone-missing')} 'SHA|workflow|authority'
    $env:GITHUB_SHA='f'*40
    Reject-Plumbing 'standalone-wrong-parent-sha' {& $standalone @standaloneOptions -OutputRoot (Join-Path $plumbing 'standalone-wrong')} 'SHA|workflow|authority'
    $env:GITHUB_SHA=$authoritySha
    Reset-PlumbingState
    & $standalone @standaloneOptions -OutputRoot (Join-Path $plumbing 'standalone-positive')
    if($global:CliBaselinePlumbing.children -ne 1 -or $global:CliBaselinePlumbing.selected -ne 1){throw 'Standalone synthetic positive missed execution phases.'}
    Write-Host 'PASS: standalone synthetic authority success'
    foreach($mutation in @('.github/workflows/cli-ci.yml','.git/config')){
        $path=Join-Path $authority $mutation;$saved=[IO.File]::ReadAllBytes($path)
        Reject-Plumbing ('selected-mutation-'+$mutation) {$global:CliBaselinePlumbing.selectedMutation=$path;& $standalone @standaloneOptions -OutputRoot (Join-Path $plumbing ('standalone-mutate-'+[guid]::NewGuid().ToString('N')))} 'inventory/content' -Children 1 -Selected 1
        [IO.File]::WriteAllBytes($path,$saved)
    }
}finally{
    $env:GITHUB_SHA=$savedGithubSha
    Remove-Item Function:\Get-FileHash,Function:\Expand-Archive
    Remove-Variable -Name CliBaselinePlumbing -Scope Global
}
