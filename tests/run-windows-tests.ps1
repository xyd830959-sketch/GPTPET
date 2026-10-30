param([switch]$WidgetOnly,[string]$PreviewDirectory,[switch]$LiveCodex)
$ErrorActionPreference='Stop'
if(!$env:GPTPET_TEST_ROOT -or ($env:GPTPET_ALLOW_TEST_CLEANUP -ne '1' -and $env:GPTPET_KEEP_TEST_FIXTURES -ne '1')){throw 'Use the isolated test runner with an explicitly approved GPTPET_TEST_ROOT.'}
$approvedRoot=[IO.Path]::GetFullPath($env:GPTPET_TEST_ROOT)
$sourceRoot=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$localRoot=[Environment]::GetFolderPath('LocalApplicationData')
$personalRoot=Join-Path $localRoot 'GPTNiangUsage'
$installedRoot=Join-Path $localRoot 'Programs\GPTNiangUsage'
$approvedRoot=$approvedRoot.TrimEnd('\')
if(![IO.Path]::IsPathRooted($env:GPTPET_TEST_ROOT) -or !$approvedRoot -or $approvedRoot+'\' -eq [IO.Path]::GetPathRoot($approvedRoot) -or $approvedRoot -ieq $sourceRoot -or $approvedRoot.StartsWith($sourceRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $approvedRoot -ieq $profileRoot -or $approvedRoot -ieq $localRoot -or $approvedRoot -ieq $personalRoot -or $approvedRoot.StartsWith($personalRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or $approvedRoot -ieq $installedRoot -or $approvedRoot.StartsWith($installedRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
  throw 'A dedicated absolute test directory is required.'
}
# Also isolate .NET temporary paths when this runner is invoked directly for LiveCodex.
$null=New-Item -ItemType Directory -Path $approvedRoot -Force
$env:GPTPET_TEST_ROOT=Join-Path $approvedRoot ('w-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$null=New-Item -ItemType Directory -Path $env:GPTPET_TEST_ROOT
$env:TEMP=$env:GPTPET_TEST_ROOT
$env:TMP=$env:GPTPET_TEST_ROOT
if($WidgetOnly){
  $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'widget.test.ps1'),[Text.Encoding]::UTF8)
  & ([ScriptBlock]::Create($source)) -TestRoot $PSScriptRoot -PreviewDirectory $PreviewDirectory
  return
}
$powerShell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach($name in @('installation.test.ps1','lifecycle.test.ps1','entrypoint.test.ps1','quote-layout.test.ps1','features.test.ps1','wallpaper-ui.test.ps1','codex-wallpaper-launcher.test.ps1')){
  & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name)
  if($LASTEXITCODE-ne 0){throw "$name failed ($LASTEXITCODE)"}
}
$widgetTestArgs=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-WidgetOnly')
if($PreviewDirectory){$widgetTestArgs+=@('-PreviewDirectory',$PreviewDirectory)}
& $powerShell @widgetTestArgs
if($LASTEXITCODE-ne 0){throw "Widget tests failed ($LASTEXITCODE)"}

if($LiveCodex){
  & $powerShell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'codex-wallpaper-launcher.test.ps1') -LiveCodex
  if($LASTEXITCODE-ne 0){throw "Live Codex CheckOnly failed ($LASTEXITCODE)"}
}
