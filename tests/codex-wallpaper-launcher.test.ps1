param([switch]$LiveCodex)
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
if(!$env:GPTPET_TEST_ROOT){throw 'An isolated test root is required.'}
$testRoot=Join-Path $env:GPTPET_TEST_ROOT 'launcher-check'
$null=New-Item -ItemType Directory -Path $testRoot -Force
$configPath=Join-Path $testRoot 'installation.json'
$node=(Get-Command node.exe -ErrorAction Stop).Source
$config=@{appDir=$source;dataDir=(Join-Path $testRoot 'state');nodePath=$node}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$profile=Join-Path $testRoot 'codex-wallpaper-profile'
$before=Test-Path -LiteralPath $profile
if(!$LiveCodex){
  $global:gptpetFakePackageRoot=Join-Path $testRoot 'WindowsApps\OpenAI.Codex_Test'
  $null=New-Item -ItemType Directory -Path (Join-Path $global:gptpetFakePackageRoot 'app') -Force
  [IO.File]::WriteAllText((Join-Path $global:gptpetFakePackageRoot 'app\ChatGPT.exe'),'synthetic fixture, never executed')
  function Get-AppxPackage {param($Name) return [pscustomobject]@{Name='OpenAI.Codex';Version='0.0.0.0';InstallLocation=$global:gptpetFakePackageRoot}}
  function Get-CimInstance {return @()}
}
$result=(& (Join-Path $source 'runtime\start-codex-wallpaper.ps1') -CheckOnly -ConfigurationPath $configPath | ConvertFrom-Json)
if(!$result.ok -or $result.codexExe -notmatch 'OpenAI\.Codex_.+\\app\\ChatGPT\.exe$' -or $result.legacyImportRequested){throw 'Store lookup or default profile opt-in is invalid.'}
if($result.profile -ne $profile -or (Test-Path -LiteralPath $profile) -ne $before){throw 'CheckOnly changed the profile directory.'}
$optedIn=(& (Join-Path $source 'runtime\start-codex-wallpaper.ps1') -CheckOnly -ImportLegacyProfile -ConfigurationPath $configPath | ConvertFrom-Json)
if(!$optedIn.legacyImportRequested -or (Test-Path -LiteralPath $profile) -ne $before){throw 'Opt-in CheckOnly must not copy a profile.'}
if($LiveCodex){Write-Output 'PASS: live Store lookup is read-only; no client was launched'}
else{Write-Output 'PASS: isolated Store lookup and explicit legacy-profile opt-in; no client was launched'}
