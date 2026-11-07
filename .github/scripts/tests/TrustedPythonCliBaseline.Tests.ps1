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
