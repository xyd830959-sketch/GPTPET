param(
  [switch]$CheckOnly,
  [string]$ConfigurationPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'installation.json')
)
$ErrorActionPreference='Stop'

$appDir=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json
if(!$config.appDir -or !$config.dataDir -or !$config.nodePath){throw 'GPT 娘安装配置不完整。'}
if(!$CheckOnly -and [IO.Path]::GetFullPath([string]$config.appDir).TrimEnd('\') -ine [IO.Path]::GetFullPath($appDir).TrimEnd('\')){
  throw '启动器与 GPT 娘正式安装目录不一致。'
}
$node=[IO.Path]::GetFullPath([string]$config.nodePath)
$wallpaperModule=Join-Path $appDir 'runtime\codex-wallpaper.mjs'
if(!(Test-Path -LiteralPath $node -PathType Leaf) -or !(Test-Path -LiteralPath $wallpaperModule -PathType Leaf)){
  throw 'GPT 娘壁纸运行文件缺失。'
}

$packages=@(Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Sort-Object Version -Descending)
if($packages.Count -ne 1){throw '无法唯一确定官方 Codex 安装。'}
$package=$packages[0]
if($package.Name -ne 'OpenAI.Codex' -or !$package.InstallLocation){throw '官方 Codex 安装信息无效。'}
$codexExe=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if(!(Test-Path -LiteralPath $codexExe -PathType Leaf)){throw '官方 Codex 程序文件不可用。'}

$dataRoot=[IO.Path]::GetFullPath((Split-Path ([IO.Path]::GetFullPath([string]$config.dataDir)) -Parent))
$profile=Join-Path $dataRoot 'codex-wallpaper-profile'
$staging=$profile+'.importing'
$marker=Join-Path $profile 'gpt-niang-profile-ready.json'
$legacy=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexDreamSkin\cdp-profile'

function Get-CodexProcesses {
  $all=@(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe' OR Name='Codex.exe'" -ErrorAction Stop)
  return @($all | Where-Object {
    ([string]$_.ExecutablePath) -match '[\\/]WindowsApps[\\/]OpenAI\.Codex_' -or
    ([string]$_.CommandLine) -match '[\\/]WindowsApps[\\/]OpenAI\.Codex_'
  })
}

function Test-LocalPort {
  $client=[Net.Sockets.TcpClient]::new()
  try {
    $task=$client.ConnectAsync('127.0.0.1',9335)
    if(!$task.Wait(500)){return $false}
    return $client.Connected
  } catch {return $false} finally {$client.Dispose()}
}

$running=@(Get-CodexProcesses)
$portBusy=Test-LocalPort
if($CheckOnly){
  [pscustomobject]@{
    ok=$true;codexExe=$codexExe;codexVersion=[string]$package.Version
    profile=$profile;profileReady=(Test-Path -LiteralPath $marker -PathType Leaf)
    legacyProfileAvailable=(Test-Path -LiteralPath $legacy -PathType Container)
    codexRunning=($running.Count -gt 0);portBusy=$portBusy
  } | ConvertTo-Json
  return
}
if($running.Count -gt 0){throw '请先完全退出 Codex，再从“Codex 壁纸模式”启动。当前会话不会被强制关闭。'}
if($portBusy){throw '本机 9335 调试端口已被占用，已停止启动以保护现有程序。'}

if(!(Test-Path -LiteralPath $marker -PathType Leaf)){
  if(Test-Path -LiteralPath $profile){throw '壁纸专用配置目录存在但未完成迁移；已保留原文件，请先检查。'}
  if(Test-Path -LiteralPath $staging){throw '上次配置迁移未完成；已保留临时副本，请先检查。'}
  $null=New-Item -ItemType Directory -Path $staging -Force
  if(Test-Path -LiteralPath $legacy -PathType Container){
    $links=@(Get-ChildItem -LiteralPath $legacy -Force -Recurse -ErrorAction Stop | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
    if($links.Count){throw '旧 Codex 配置含目录链接，已停止迁移。'}
    Get-ChildItem -LiteralPath $legacy -Force -ErrorAction Stop |
      Where-Object {$_.Name -notmatch '^(lockfile|Singleton.*)$'} |
      Copy-Item -Destination $staging -Recurse -Force -ErrorAction Stop
  }
  [IO.File]::WriteAllText((Join-Path $staging 'gpt-niang-profile-ready.json'),
    (@{createdAt=[DateTime]::UtcNow.ToString('o');source=if(Test-Path -LiteralPath $legacy){'legacy-cdp-profile'}else{'new-profile'}} | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false))
  [IO.Directory]::Move($staging,$profile)
}

$arguments='--remote-debugging-address=127.0.0.1 --remote-debugging-port=9335 "--user-data-dir='+$profile+'"'
$process=Start-Process -FilePath $codexExe -ArgumentList $arguments -PassThru -ErrorAction Stop
$process.Dispose()
$deadline=(Get-Date).AddSeconds(45)
$ready=$false
do {
  try {
    $version=Invoke-RestMethod -Uri 'http://127.0.0.1:9335/json/version' -TimeoutSec 2 -ErrorAction Stop
    if($version.webSocketDebuggerUrl -match '^ws://(127\.0\.0\.1|localhost):9335/devtools/browser/'){$ready=$true}
  } catch {}
  if(!$ready){Start-Sleep -Milliseconds 500}
} while(!$ready -and (Get-Date) -lt $deadline)
if(!$ready){throw 'Codex 已启动，但没有开放壁纸连接。请正常使用 Codex；此版本可能不支持调试端口。'}
$listeners=@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 9335 -State Listen -ErrorAction Stop)
if($listeners.Count -ne 1){throw 'Codex 已启动，但无法唯一确认壁纸连接的所属进程。'}
$owner=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$listeners[0].OwningProcess) -ErrorAction Stop
if(!$owner -or [string]$owner.ExecutablePath -ine $codexExe){throw '壁纸连接不属于官方 Codex，已停止应用。'}

$statePath=Join-Path ([string]$config.dataDir) 'codex-wallpaper\state.json'
$enabled=$false
try {$enabled=(Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).enabled -eq $true} catch {}
if($enabled){
  $applied=$false
  $deadline=(Get-Date).AddSeconds(60)
  do {
    $previousErrorActionPreference=$ErrorActionPreference
    try {
      # A page may not exist yet. Native stderr is an ErrorRecord in Windows PowerShell.
      $ErrorActionPreference='Continue'
      $reply=(& $node $wallpaperModule apply ([string]$config.dataDir) - 2>$null | Out-String)
      $applyExitCode=$LASTEXITCODE
    } finally {
      $ErrorActionPreference=$previousErrorActionPreference
    }
    try {$applied=$applyExitCode -eq 0 -and ($reply.Trim() | ConvertFrom-Json).ok -eq $true} catch {$applied=$false}
    if(!$applied -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 700}
  } while(!$applied -and (Get-Date) -lt $deadline)
  if(!$applied){throw 'Codex 已正常启动，但壁纸尚未应用；可在 GPT 娘设置中点“应用壁纸”。'}
}
Write-Output 'Codex 已由 GPT 娘独立启动，壁纸连接可用。'
