param(
  [string]$FfmpegPath,
  [string]$CodexPath,
  [string]$NodePath,
  [string]$DataDir,
  [string]$Workspace=(Get-Location).Path,
  [string]$WallpaperDataDir,
  [switch]$CheckOnly,
  [switch]$ConfigureOnly,
  [switch]$Stop
)
$ErrorActionPreference='Stop'
$app=[IO.Path]::GetFullPath($PSScriptRoot)
$configFile=Join-Path $app 'installation.json'
$previous=$null
if(Test-Path -LiteralPath $configFile){
  $previous=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8|ConvertFrom-Json
  if([IO.Path]::GetFullPath([string]$previous.appDir).TrimEnd('\')-ine $app.TrimEnd('\')){throw 'This configuration belongs to another source folder. Use a fresh source checkout.'}
}
if(!$DataDir){$DataDir=if($previous.dataDir){[string]$previous.dataDir}else{Join-Path $app 'state'}}
$data=[IO.Path]::GetFullPath($DataDir)
if($Stop){
  if(!$CheckOnly){$null=[IO.Directory]::CreateDirectory($data);[IO.File]::WriteAllText((Join-Path $data 'stop.flag'),'stop fox preview',[Text.UTF8Encoding]::new($false))}
  return
}
if(!$NodePath){$command=Get-Command node.exe -ErrorAction SilentlyContinue;if($command){$NodePath=$command.Source}}
if(!$NodePath -or !(Test-Path -LiteralPath $NodePath -PathType Leaf)){throw 'Node.js 22 or newer is required; use -NodePath if it is not on PATH.'}
$NodePath=[IO.Path]::GetFullPath($NodePath)
$nodeVersion=(& $NodePath --version).Trim()
if($LASTEXITCODE-ne 0 -or $nodeVersion-notmatch '^v(\d+)\.' -or [int]$Matches[1]-lt 22){throw 'Node.js 22 or newer is required.'}
if(!$CodexPath){$command=Get-Command codex.exe -ErrorAction SilentlyContinue;if($command){$CodexPath=$command.Source}}
if(!$CodexPath -or !(Test-Path -LiteralPath $CodexPath -PathType Leaf)){
  $local=[Environment]::GetFolderPath('LocalApplicationData')
  if($local){
    $bundled=Join-Path $local 'OpenAI\Codex\bin'
    if(Test-Path -LiteralPath $bundled){$CodexPath=(Get-ChildItem -LiteralPath $bundled -Filter codex.exe -File -Recurse|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1).FullName}
  }
}
if(!$CodexPath -or !(Test-Path -LiteralPath $CodexPath -PathType Leaf)){throw 'Codex desktop CLI was not found. Use -CodexPath to specify an existing installation.'}
if(!$FfmpegPath){
  $localDecoder=Join-Path $app 'runtime\ffmpeg\ffmpeg.exe'
  if(Test-Path -LiteralPath $localDecoder -PathType Leaf){$FfmpegPath=$localDecoder}
  else{$command=Get-Command ffmpeg.exe -ErrorAction SilentlyContinue;if($command){$FfmpegPath=$command.Source}}
}
if(!$FfmpegPath -or !(Test-Path -LiteralPath $FfmpegPath -PathType Leaf)){throw 'A separately supplied FFmpeg executable is required. Use -FfmpegPath; see runtime/ffmpeg/README.md.'}
$FfmpegPath=[IO.Path]::GetFullPath($FfmpegPath)
$decoders=(& $FfmpegPath -hide_banner -decoders 2>&1|Out-String)
if($LASTEXITCODE-ne 0 -or $decoders-notmatch '\blibvpx-vp9\b'){throw 'FFmpeg must support the libvpx-vp9 decoder for transparent playback.'}
$manifest=Join-Path $app 'assets\fox-spirit\animation-manifest.json'
$description=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
$assetRoot=[IO.Path]::GetFullPath((Split-Path $manifest -Parent)).TrimEnd('\')+'\'
$relative=@($description.stills.PSObject.Properties|ForEach-Object{$_.Value})
$relative+=@($description.clips.PSObject.Properties|ForEach-Object{$_.Value.path})
$relative+=@($description.actions.PSObject.Properties|ForEach-Object{$_.Value.path})
foreach($name in $relative){
  if(!$name -or [IO.Path]::IsPathRooted([string]$name)){throw 'Invalid character asset path.'}
  $file=[IO.Path]::GetFullPath((Join-Path $assetRoot $name))
  if(!$file.StartsWith($assetRoot,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $file -PathType Leaf)){throw ('Missing or invalid character asset: '+$name)}
}
$config=@{version='1.3.0-preview.1';appDir=$app;dataDir=$data;nodePath=$NodePath;codexPath=[IO.Path]::GetFullPath($CodexPath);
  marketplaceRoot=(Split-Path $app -Parent);startupShortcut=(Join-Path $data 'unused-startup.lnk');
  animationManifest=$manifest;animationFfmpegPath=$FfmpegPath;completionWorkspace=[IO.Path]::GetFullPath($Workspace)}
if($WallpaperDataDir){$config.wallpaperDataDir=[IO.Path]::GetFullPath($WallpaperDataDir)}
elseif($previous.wallpaperDataDir){$config.wallpaperDataDir=[string]$previous.wallpaperDataDir}
if($CheckOnly){[pscustomobject]@{ok=$true;source=$app;dataDir=$data;nodeVersion=$nodeVersion;characterAssets=$relative.Count;configurationWritten=$false;startupRegistered=$false}|ConvertTo-Json;return}
$null=[IO.Directory]::CreateDirectory($data)
$temporary=$configFile+'.new'
if(Test-Path -LiteralPath $temporary){throw 'A previous configuration write is still present; inspect it before retrying.'}
[IO.File]::WriteAllText($temporary,($config|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if(Test-Path -LiteralPath $configFile){[IO.File]::Replace($temporary,$configFile,$configFile+'.previous')}
else{[IO.File]::Move($temporary,$configFile)}
if($ConfigureOnly){return}
$arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $app 'runtime\start-widget.ps1')+'"'))
$process=Start-Process -FilePath powershell.exe -ArgumentList $arguments -WorkingDirectory $app -WindowStyle Hidden -PassThru
$process.Dispose()
