$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $PSScriptRoot -Parent
if(!$env:GPTPET_TEST_ROOT){throw 'An isolated test root is required.'}
$script:dataDir=Join-Path $env:GPTPET_TEST_ROOT 'ui-menu'
$script:window=New-Object Windows.Window
$script:collapsed=$true
$script:bubbleMode='quota'
$script:scale=1.0
$script:soundOn=$true
$script:persistedSoundVolume=0.5
$script:colorMode='original'
$script:colorChance=0
$script:colorTextChance=0
$script:settingsReady=$false
. (Join-Path $script:appDir 'runtime\ui-settings.ps1')
. (Join-Path $script:appDir 'runtime\wallpaper-ui.ps1')
$script:wallpaperModuleAvailable=$true
try {
  Initialize-WidgetSettingsMenu
  if(!$script:settingsMenuUi.Wallpaper){throw 'Codex personalization menu is missing.'}
  if(!$script:settingsMenuUi.WallpaperDimming -or $script:settingsMenuUi.WallpaperDimming.Value -ne 60){throw 'Wallpaper dimming slider should default to 60%.'}
  if($script:settingsMenuUi.WallpaperEnable.IsChecked){throw 'Wallpaper must be disabled by default.'}
  if($script:settingsMenuUi.WallpaperApply.IsEnabled){throw 'Apply must be disabled without an imported wallpaper.'}
  if(!$script:settingsMenuUi.Audio -or !$script:settingsMenuUi.Appearance){throw 'Existing settings menu items are missing.'}
  $node=(Get-Command node -ErrorAction Stop).Source
  $module=Join-Path $script:appDir 'runtime\codex-wallpaper.mjs'
  $result=Join-Path $script:dataDir 'wallpaper-process-result.json'
  $null=New-Item -ItemType Directory -Path $script:dataDir -Force
  $arguments=Get-WallpaperProcessArguments $module 'status' $script:dataDir '' $result
  $process=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
  if($process.ExitCode -ne 0){throw 'Wallpaper background process failed.'}
  $reply=Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
  if(!$reply.ok -or $reply.enabled){throw 'Wallpaper background process returned an invalid or enabled state.'}
  Write-Output 'PASS: original settings and disabled wallpaper submenu coexist'
} finally { $script:window.Close() }
