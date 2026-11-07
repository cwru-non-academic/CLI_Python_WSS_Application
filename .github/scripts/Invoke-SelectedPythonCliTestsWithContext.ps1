[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CoreRoot,[Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$RootsPath,[Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$WorkRoot,[string]$PythonExecutable='python'
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/SelectedProcessIsolation.ps1"
. "$PSScriptRoot/SelectedTestContext.ps1"
$binding=Invoke-ReviewedSelectionCore $CoreRoot inspect 'python-cli' $ContextPath $RootsPath
$roots=Get-Content -LiteralPath $RootsPath -Raw | ConvertFrom-Json
$product=Get-SelectedProduct $roots 'cwru-non-academic/CLI_Python_WSS_Application'
$wrapper=Get-SelectedProduct $roots 'cwru-non-academic/Python_WSS_Integration_Lib'
if(Test-Path -LiteralPath $WorkRoot){throw 'Selected suite work directory must be new.'}
$arguments=@('-B',"$PSScriptRoot/invoke_selected_cli_tests.py",'--product-root',$product.path,'--product-sha',$product.commit,
    '--wrapper-root',$wrapper.path,'--wrapper-sha',$wrapper.commit,'--payload-root',$PayloadRoot,
    '--test-root',$roots.test_root,'--test-sha',$binding.test_commit,'--test-repository',$binding.test_repository,
    '--test-selection-id',$binding.selection_id,'--evidence',(Join-Path $WorkRoot 'test-source-evidence.json'))
Invoke-CredentialFreeSelectedProcess (Get-Command $PythonExecutable -ErrorAction Stop).Source $arguments
# Existing wrapper canonical/native gates remain mandatory in the calling workflow.
Invoke-ReviewedSelectionCore $CoreRoot evidence 'python-cli' $ContextPath $RootsPath (Join-Path $WorkRoot 'selection/evidence.json')