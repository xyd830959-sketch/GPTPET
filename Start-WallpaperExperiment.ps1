param(
  [string]$InstalledConfig=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\GPTNiangUsage\gpt-niang-usage\installation.json'),
  [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$appDir=$PSScriptRoot
$workspace=Split-Path $appDir -Parent
$dataDir=Join-Path $workspace 'experiment-data'
$configPath=Join-Path $appDir 'installation.json'
$installed=Get-Content -LiteralPath $InstalledConfig -Raw -Encoding UTF8 | ConvertFrom-Json
if(!(Test-Path -LiteralPath $installed.nodePath)){throw 'Node.js 运行环境不可用。'}
if(!(Test-Path -LiteralPath $installed.codexPath)){throw 'Codex 命令行程序不可用。'}
$config=@{
  version='1.2.5-wallpaper-experiment'
  appDir=$appDir
  dataDir=$dataDir
  nodePath=$installed.nodePath
  codexPath=$installed.codexPath
  marketplaceRoot=$workspace
}
if($CheckOnly){$config | ConvertTo-Json;return}
if(Test-Path -LiteralPath $configPath){
  $existing=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($existing.appDir -ine $appDir -or $existing.dataDir -ine $dataDir){throw '实验配置指向其他目录，已停止启动。'}
}
$null=New-Item -ItemType Directory -Path $dataDir -Force
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $appDir 'runtime\start-widget.ps1')
if($LASTEXITCODE -ne 0){throw "实验版启动失败（退出码 $LASTEXITCODE）。"}
