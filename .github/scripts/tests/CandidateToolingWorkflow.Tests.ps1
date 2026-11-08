param([Parameter(Mandatory)][string]$ToolsRoot)
# Execute actual caller/reusable workflow blocks with fabricated Git checkouts.
# Shared runner is a nonloading sentinel; no producer, native or WSS code runs.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Read-Workflow([string]$Path){
 $raw=& python -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))))' $Path
 if($LASTEXITCODE){throw 'Cannot parse workflow.'};($raw -join [Environment]::NewLine)|ConvertFrom-Json -AsHashtable
}
$workflow=Read-Workflow (Join-Path $root '.github/workflows/wss-preflight.yml')
$reusable=Read-Workflow (Join-Path $ToolsRoot '.github/workflows/_python-validation.yml')
$ordinary=Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
$pin=$workflow.jobs.tooling.steps[1].with.ref
if($pin -cnotmatch '^[a-f0-9]{40}$' -or !$ordinary.Contains("ref: $pin")){throw 'Missing immutable ordinary/candidate agreement.'}
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('cli candidate tooling '+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $sandbox
$keys=@('GITHUB_WORKSPACE','GITHUB_SHA','GITHUB_WORKFLOW_SHA','GITHUB_REPOSITORY','GITHUB_EVENT_NAME','GITHUB_REF','GITHUB_REF_NAME','GITHUB_WORKFLOW_REF','GITHUB_OUTPUT','RUNNER_TEMP','ROLE','MODE','WRAPPER_SHA','CLI_SHA','TOOLS_SHA','WSS_CI_CHANNEL','CLI_TOOLING_SENTINEL')
$saved=@{};foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key)}
$count=0
function Write-Fixture([string]$Path,[string]$Text){$null=New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force;[IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Commit-Fixture([string]$Path){& git -C $Path -c core.autocrlf=false add .;if($LASTEXITCODE){throw 'Fixture add failed.'};& git -C $Path -c user.name=Fixture -c user.email=fixture@example.invalid -c core.autocrlf=false commit -qm fixture;if($LASTEXITCODE){throw 'Fixture commit failed.'};(& git -C $Path rev-parse HEAD).Trim()}
function New-Fixture {
 $workspace=Join-Path $sandbox ([guid]::NewGuid().ToString('N'))
 $tools=Join-Path $workspace 'tools';$source=Join-Path $workspace 'source'
 $sentinel=@'
param([string]$ToolsRoot,[string]$ToolsSha,[string]$ConfigPath,[string]$WrapperRoot,[string]$WrapperSha,[string]$CliRoot,[string]$CliSha,[string]$FixtureRoot,[string]$OutputRoot,[string]$Mode,[string]$Role,[string]$ArtifactRoot,[string]$CandidatePath)
$PSBoundParameters | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:CLI_TOOLING_SENTINEL
throw 'CLI_SYNTHETIC_CHILD_BOUNDARY'
'@
 $tooling=@'
function Assert-PythonToolingBinding([string]$Root,[string]$Sha,[string]$Config){
 if([IO.Path]::GetFullPath($Root) -cne [IO.Path]::GetFullPath((Join-Path $env:GITHUB_WORKSPACE 'tools')) -or $Sha -cne $env:TOOLS_SHA -or [IO.Path]::GetFullPath($Config) -cne [IO.Path]::GetFullPath((Join-Path $Root '.github/python-ci.json'))){throw 'Synthetic tooling binding differs.'}
}
'@
 Write-Fixture (Join-Path $tools '.github/scripts/PythonContract.ps1') '# Synthetic nonloading contract.'
 Write-Fixture (Join-Path $tools '.github/scripts/PythonProfiles/Tooling.ps1') $tooling
 Write-Fixture (Join-Path $tools '.github/scripts/Invoke-DotNetConformance.ps1') $sentinel
 Write-Fixture (Join-Path $tools '.github/python-ci.json') '{"fixture_commit":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'
 & git -C $tools init -q;$toolSha=Commit-Fixture $tools
 Write-Fixture (Join-Path $source '.github/workflows/cli-ci.yml') ($ordinary.Replace($pin,$toolSha))
 Write-Fixture (Join-Path $source '.github/scripts/Read-OrdinaryPythonTooling.ps1') (Get-Content (Join-Path $root '.github/scripts/Read-OrdinaryPythonTooling.ps1') -Raw)
 $config=@{automated_execution='pythonnet';dotnet_sdk='9.0.316';baseline_ready=$true;channels=@('dev','main');fixture_commit=('c'*40)}|ConvertTo-Json
 Write-Fixture (Join-Path $source '.github/python-ci.json') $config
 & git -C $source init -q;$sourceSha=Commit-Fixture $source
 Copy-Item -LiteralPath $source -Destination (Join-Path $workspace 'caller') -Recurse
 Write-Fixture (Join-Path $workspace 'candidate-contract/.github/python-ci.json') $config
 foreach($path in @('wrapper','fixture','cli','runner')){$null=New-Item -ItemType Directory -Path (Join-Path $workspace $path)}
 @{workspace=$workspace;tools=$tools;source=$source;toolsSha=$toolSha;sourceSha=$sourceSha;fixtureSha=('c'*40);wrapperSha=('b'*40)}
}
function Step($Job,[string]$Name){$matches=@($Job.steps|Where-Object {$_.Contains('name') -and $_.name -ceq $Name});if($matches.Count -ne 1){throw "Missing or ambiguous workflow step $Name"};$matches[0]}
function Checkout($Job,[string]$Path){$matches=@($Job.steps|Where-Object {$_.Contains('uses') -and $_.uses -ceq 'actions/checkout@v4' -and $_.Contains('with') -and $_.with.Contains('path') -and $_.with.path -ceq $Path});if($matches.Count -ne 1){throw "Missing or ambiguous checkout $Path"};$matches[0].with}
function Assert-Wiring($Caller,$Called){
 $source=Checkout $Caller.jobs.tooling 'source';$tools=Checkout $Caller.jobs.tooling 'tools'
 if($source.ref -cne '${{ github.sha }}' -or $source['persist-credentials'] -ne $false -or $tools.repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $tools.ref -cne $pin -or $tools['persist-credentials'] -ne $false){throw 'Caller checkout routing changed.'}
 if($Caller.jobs.validate.needs -cne 'tooling' -or $Caller.jobs.validate.with.tools_sha -cne '${{ needs.tooling.outputs.tools_sha }}' -or $Caller.jobs.tooling.outputs.tools_sha -cne '${{ steps.binding.outputs.tools_sha }}' -or $Caller.jobs.validate.uses -cne "cwru-non-academic/Python_WSS_Integration_Lib/.github/workflows/_python-validation.yml@$pin"){throw 'Caller tooling/callee binding changed.'}
 if($Caller.jobs.validate.with.role -cne 'cli' -or $Caller.jobs.validate.with.mode -cne 'candidate' -or $Caller.jobs.validate.with.wrapper_sha -cne '${{ inputs.wrapper_sha }}' -or $Caller.jobs.validate.with.cli_sha -cne '${{ inputs.cli_sha }}' -or $Caller.jobs.validate.with.candidate_json -cne '${{ inputs.candidate_json }}'){throw 'Caller role/mode/product forwarding changed.'}
 $binding=Step $Caller.jobs.tooling 'Verify caller-owned immutable tooling pin'
 if($binding.id -cne 'binding' -or $binding.Contains('if') -or $binding.Contains('continue-on-error')){throw 'Caller tooling binding cannot be bypassed.'}
 $sourceIndex=-1;$toolIndex=-1;$bindingIndex=-1
 for($i=0;$i -lt $Caller.jobs.tooling.steps.Count;$i++){
  $step=$Caller.jobs.tooling.steps[$i]
  if($step.Contains('with') -and $step.with.Contains('path')){if($step.with.path -ceq 'source'){$sourceIndex=$i};if($step.with.path -ceq 'tools'){$toolIndex=$i}}
  if([object]::ReferenceEquals($step,$binding)){$bindingIndex=$i}
 }
 if($sourceIndex -lt 0 -or $toolIndex -lt 0 -or $sourceIndex -ge $bindingIndex -or $toolIndex -ge $bindingIndex){throw 'Caller binding must follow its exact source/tool checkouts.'}

 $inputs=if($Called.Contains('on')){$Called.on.workflow_call.inputs}else{$Called['true'].workflow_call.inputs}
 if($inputs.tools_sha.required -ne $true){throw 'Reusable tooling input must be required.'}
 foreach($job in @('prerequisites','conformance')){
  $auth=Step $Called.jobs[$job] 'Authenticate registered reusable caller and tooling identity'
  $verify=Step $Called.jobs[$job] 'Verify immutable tooling before importing validators'
  if($auth.Contains('if') -or $auth.Contains('continue-on-error') -or $verify.Contains('if') -or $verify.Contains('continue-on-error')){throw 'Reusable authentication cannot be bypassed.'}
  $positions=@{}
  for($i=0;$i -lt $Called.jobs[$job].steps.Count;$i++){
   $step=$Called.jobs[$job].steps[$i]
   if([object]::ReferenceEquals($step,$auth)){$positions.auth=$i}
   if([object]::ReferenceEquals($step,$verify)){$positions.verify=$i}
   if($step.Contains('with') -and $step.with.Contains('path') -and $step.with.path -cin @('tools','caller')){$positions[$step.with.path]=$i}
  }
  if($positions.auth -ge $positions.tools -or $positions.auth -ge $positions.caller -or $positions.verify -le $positions.tools -or $positions.verify -le $positions.caller){throw 'Reusable authentication and verified imports must surround checkouts.'}

  $tools=Checkout $Called.jobs[$job] 'tools';$caller=Checkout $Called.jobs[$job] 'caller'
  if($tools.ref -cne '${{ inputs.tools_sha }}' -or $tools.repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $caller.ref -cne '${{ github.sha }}' -or $caller.repository -cne '${{ github.repository }}'){throw 'Reusable tooling/caller checkout routing changed.'}
 }
 $product=Checkout $Called.jobs.prerequisites 'candidate-contract';$wrapper=Checkout $Called.jobs.conformance 'wrapper';$fixture=Checkout $Called.jobs.conformance 'fixture';$cli=Checkout $Called.jobs.conformance 'cli'
 if($product.ref -cne '${{ inputs.wrapper_sha }}' -or $product.repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or $wrapper.ref -cne '${{ needs.prerequisites.outputs.wrapper }}' -or $fixture.ref -cne '${{ needs.prerequisites.outputs.fixture }}' -or $fixture.repository -cne 'cwru-non-academic/CSharp_WSS_Integration_Lib' -or $cli.ref -cne '${{ needs.prerequisites.outputs.cli }}'){throw 'Product/fixture routing changed.'}
}
function Invoke-Fixture($Caller,$Called,[string]$Channel='dev',[string]$Mutation=''){
 Assert-Wiring $Caller $Called;$f=New-Fixture
 $env:GITHUB_WORKSPACE=$f.workspace;$env:GITHUB_SHA=$f.sourceSha;$env:GITHUB_WORKFLOW_SHA=$f.sourceSha;$env:GITHUB_REPOSITORY='cwru-non-academic/CLI_Python_WSS_Application';$env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REF="refs/heads/$Channel";$env:GITHUB_REF_NAME=$Channel;$env:WSS_CI_CHANNEL=$Channel;$env:GITHUB_WORKFLOW_REF="$env:GITHUB_REPOSITORY/.github/workflows/wss-preflight.yml@$env:GITHUB_REF"
 $env:GITHUB_OUTPUT=Join-Path $f.workspace 'bindings.txt';$env:RUNNER_TEMP=Join-Path $f.workspace 'runner';$env:ROLE='cli';$env:MODE='candidate';$env:WRAPPER_SHA=$f.wrapperSha;$env:CLI_SHA=$f.sourceSha;$env:TOOLS_SHA=$f.toolsSha;$env:CLI_TOOLING_SENTINEL=Join-Path $f.workspace 'sentinel.json'
 switch($Mutation){
  'wrong-repository'{$env:GITHUB_REPOSITORY='example/wrong'}
  'wrong-event'{$env:GITHUB_EVENT_NAME='push'}
  'wrong-workflow'{$env:GITHUB_WORKFLOW_REF='other'}
  'wrong-source'{$env:GITHUB_SHA='f'*40}
  'wrong-workflow-source'{$env:GITHUB_WORKFLOW_SHA='f'*40}
  'wrong-channel'{$env:WSS_CI_CHANNEL='other'}
  'wrong-role'{$env:ROLE='wrapper'}
  'unknown-role'{$env:ROLE='other'}
  'wrong-cli-source'{$env:CLI_SHA='f'*40}
  'wrong-product-source'{$env:WRAPPER_SHA='main'}
  'wrong-tools-source'{$env:TOOLS_SHA='f'*40}
  'dirty-tools'{[IO.File]::AppendAllText((Join-Path $f.tools '.github/python-ci.json'),'dirty')}
  'dirty-source'{[IO.File]::AppendAllText((Join-Path $f.source '.github/workflows/cli-ci.yml'),'dirty')}
  'unadopted-main'{$configPath=Join-Path $f.workspace 'candidate-contract/.github/python-ci.json';$cfg=Get-Content $configPath -Raw|ConvertFrom-Json;$cfg.channels=@('dev');Write-Fixture $configPath ($cfg|ConvertTo-Json)}
 }
 Push-Location $f.workspace
 try{
  & ([scriptblock]::Create((Step $Caller.jobs.tooling 'Verify caller-owned immutable tooling pin').run))
  $lines=Get-Content -LiteralPath $env:GITHUB_OUTPUT
  if(@($lines|Where-Object {$_ -ceq "tools_sha=$($f.toolsSha)"}).Count -ne 1){throw 'Caller did not emit exact tools SHA.'}
  foreach($job in @('prerequisites','conformance')){
   & ([scriptblock]::Create((Step $Called.jobs[$job] 'Authenticate registered reusable caller and tooling identity').run))
   & ([scriptblock]::Create((Step $Called.jobs[$job] 'Verify immutable tooling before importing validators').run))
  }
  & ([scriptblock]::Create((Step $Called.jobs.prerequisites 'Validate exact source and execution contract').run))
  $lines=Get-Content -LiteralPath $env:GITHUB_OUTPUT
  foreach($line in @("wrapper=$($f.wrapperSha)","cli=$($f.sourceSha)","fixture=$($f.fixtureSha)")){if(@($lines|Where-Object {$_ -ceq $line}).Count -ne 1){throw 'Product/fixture output selection changed.'}}
  $run=(Step $Called.jobs.conformance 'Execute canonical cases through shared production wrapper source').run.Replace('${{ inputs.tools_sha }}',$f.toolsSha)
  try {& ([scriptblock]::Create($run));throw 'Runner did not stop before product runtime.'}catch{if($_.Exception.Message -cne 'CLI_SYNTHETIC_CHILD_BOUNDARY'){throw}}
 }finally{Pop-Location}
 $actual=Get-Content -LiteralPath $env:CLI_TOOLING_SENTINEL -Raw|ConvertFrom-Json -AsHashtable
 $expected=@{ToolsRoot=$f.tools;ToolsSha=$f.toolsSha;ConfigPath=(Join-Path $f.tools '.github/python-ci.json');WrapperRoot=(Join-Path $f.workspace 'wrapper');WrapperSha=$f.wrapperSha;CliRoot=(Join-Path $f.workspace 'cli');CliSha=$f.sourceSha;FixtureRoot=(Join-Path $f.workspace 'fixture');OutputRoot=(Join-Path $env:RUNNER_TEMP 'conformance-results');Mode='candidate';Role='cli';ArtifactRoot=(Join-Path $env:RUNNER_TEMP 'resolved/extracted/WSS-Universal');CandidatePath=(Join-Path $env:RUNNER_TEMP 'resolved/candidate.json')}
 foreach($key in $expected.Keys){if(!$actual.Contains($key)){throw "Missing runner argument $key"};$a=[string]$actual[$key];$b=[string]$expected[$key];if($key -match 'Root$|Path$'){$a=[IO.Path]::GetFullPath($a);$b=[IO.Path]::GetFullPath($b)};if($a -cne $b){throw "Wrong runner argument $key"}}
 $script:count++
}
function Reject([string]$Name,[scriptblock]$Action){$caught=$false;try{& $Action}catch{$caught=$true};if(!$caught){throw "Accepted candidate mutation $Name"};$script:count++}
try{
 foreach($channel in @('dev','main')){Invoke-Fixture $workflow $reusable $channel}
 foreach($mutation in @('wrong-repository','wrong-event','wrong-workflow','wrong-source','wrong-workflow-source','wrong-channel','wrong-role','unknown-role','wrong-cli-source','wrong-product-source','wrong-tools-source','dirty-tools','dirty-source','unadopted-main')){Reject $mutation {Invoke-Fixture $workflow $reusable 'main' $mutation}}
 foreach($mutation in @('caller-role','caller-mode','early-binding','bypass-binding','late-auth','wrong-product-checkout','mutable-tools','wrong-tool-repository','missing-tools-output','product-tools-ref','wrong-callee-pin','missing-tools-argument','wrong-tools-argument','product-config','wrong-role-argument','wrong-fixture-argument')){
  $caller=$workflow|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable;$called=$reusable|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable
  switch($mutation){
   'caller-role'{$caller.jobs.validate.with.role='wrapper'}
   'caller-mode'{$caller.jobs.validate.with.mode='committed'}
   'early-binding'{$steps=$caller.jobs.tooling.steps;$caller.jobs.tooling.steps=@($steps[2],$steps[0],$steps[1])}
   'bypass-binding'{(Step $caller.jobs.tooling 'Verify caller-owned immutable tooling pin')['if']='false'}
   'late-auth'{$steps=$called.jobs.conformance.steps;$called.jobs.conformance.steps=@($steps[1],$steps[0])+@($steps|Select-Object -Skip 2)}
   'wrong-product-checkout'{(Checkout $called.jobs.prerequisites 'candidate-contract').ref='${{ inputs.tools_sha }}'}

   'mutable-tools'{$caller.jobs.tooling.steps[1].with.ref='main'}
   'wrong-tool-repository'{$caller.jobs.tooling.steps[1].with.repository='example/wrong'}
   'missing-tools-output'{$caller.jobs.validate.with.tools_sha=''}
   'product-tools-ref'{(Checkout $called.jobs.conformance 'tools').ref='${{ inputs.wrapper_sha }}'}
   'wrong-callee-pin'{$caller.jobs.validate.uses=$caller.jobs.validate.uses.Replace($pin,('f'*40))}
   default{
    $step=Step $called.jobs.conformance 'Execute canonical cases through shared production wrapper source'
    switch($mutation){
     'missing-tools-argument'{$step.run=$step.run.Replace('ToolsSha =','UnusedSha =')}
     'wrong-tools-argument'{$step.run=$step.run.Replace('ToolsSha = ''${{ inputs.tools_sha }}''',("ToolsSha = '"+('f'*40)+"'"))}
     'product-config'{$step.run=$step.run.Replace('ConfigPath = "$env:GITHUB_WORKSPACE/tools/.github/python-ci.json"','ConfigPath = "$env:GITHUB_WORKSPACE/wrapper/.github/python-ci.json"')}
     'wrong-role-argument'{$step.run=$step.run.Replace('Role = $env:ROLE',"Role = 'wrapper'")}
     'wrong-fixture-argument'{$step.run=$step.run.Replace('FixtureRoot = "$env:GITHUB_WORKSPACE/fixture"','FixtureRoot = "$env:GITHUB_WORKSPACE/tools"')}
    }
   }
  }
  Reject $mutation {Invoke-Fixture $caller $called}
 }
 Write-Output "PASS: $count actual CLI caller/reusable checkout/runner routes and mutations; product/fixture authority preserved."
}finally{
 foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])}
 $full=[IO.Path]::GetFullPath($sandbox);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
 if(!$full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notlike 'cli candidate tooling *'){throw 'Unsafe fixture cleanup target.'}
 Remove-Item -LiteralPath $full -Recurse -Force
}
