[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CoreRoot,[Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$RootsPath,[Parameter(Mandatory)][string]$ToolsRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][ValidateSet('committed','candidate')][string]$Mode,
    [string]$FixtureRoot='', [string]$ArtifactRoot='', [string]$CandidatePath='',
    [string]$PythonExecutable='python'
)
$ErrorActionPreference='Stop'
$PythonExecutable=(Get-Command $PythonExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
. "$PSScriptRoot/SelectedProcessIsolation.ps1"
. "$PSScriptRoot/SelectedTestContext.ps1"
. "$PSScriptRoot/TrustedPythonCliBaseline.ps1"
# Freeze authority bytes before inspect; selected code cannot rewrite the caller's
# lock, Core source or context/roots and then exploit a mutable Git index/config.
$authority=New-TrustedBaselineSnapshot @($PSScriptRoot,$CoreRoot,$ContextPath,$RootsPath)
$binding=Invoke-ReviewedSelectionCore $CoreRoot inspect 'python-cli' $ContextPath $RootsPath
$roots=Get-Content -LiteralPath $RootsPath -Raw | ConvertFrom-Json
$product=Get-SelectedProduct $roots 'cwru-non-academic/CLI_Python_WSS_Application'
$wrapper=Get-SelectedProduct $roots 'cwru-non-academic/Python_WSS_Integration_Lib'
if(Test-Path -LiteralPath $WorkRoot){throw 'Selected suite work directory must be new.'}
# A new baseline is executed here, never imported from a prior/selected child.
$baseline=Invoke-TrustedPythonCliBaseline -ToolsRoot $ToolsRoot -WrapperRoot $wrapper.path -WrapperSha $wrapper.commit `
    -CliRoot $product.path -CliSha $product.commit -OutputRoot ($WorkRoot+'-baseline') -Mode $Mode `
    -FixtureRoot $FixtureRoot -ArtifactRoot $ArtifactRoot -CandidatePath $CandidatePath -PythonExecutable $PythonExecutable
Assert-TrustedBaselineSnapshot $authority
$protected=New-TrustedBaselineSnapshot @($baseline.root,$baseline.payload_root,$ToolsRoot,$product.path,$wrapper.path)
$arguments=@('-B',"$PSScriptRoot/invoke_selected_cli_tests.py",'--product-root',$product.path,'--product-sha',$product.commit,
    '--wrapper-root',$wrapper.path,'--wrapper-sha',$wrapper.commit,'--payload-root',$baseline.payload_root,
    '--test-root',$roots.test_root,'--test-sha',$binding.test_commit,'--test-repository',$binding.test_repository,
    '--test-selection-id',$binding.selection_id,'--evidence',(Join-Path $WorkRoot 'test-source-evidence.json'))
Invoke-CredentialFreeSelectedProcess $PythonExecutable $arguments
# Recheck using already-loaded parent code BEFORE launching any Core node process.
Assert-TrustedBaselineSnapshot $authority
Assert-TrustedBaselineSnapshot $protected
# Existing native/platform gates remain mandatory in the secret-free executor's
# reviewed caller workflow. This local canonical proof does not replace them.
Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-cli' $ContextPath $RootsPath (Join-Path $WorkRoot 'selection/evidence.json')
