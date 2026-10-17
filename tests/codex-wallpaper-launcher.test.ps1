$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path (Split-Path $source -Parent) 'verification-data\launcher-check'
$null=New-Item -ItemType Directory -Path $testRoot -Force
$configPath=Join-Path $testRoot 'installation.json'
$node=(Get-Command node.exe -ErrorAction Stop).Source
$config=@{appDir=$source;dataDir=(Join-Path $testRoot 'state');nodePath=$node}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$profile=Join-Path $testRoot 'codex-wallpaper-profile'
$before=Test-Path -LiteralPath $profile
$result=(& (Join-Path $source 'runtime\start-codex-wallpaper.ps1') -CheckOnly -ConfigurationPath $configPath | ConvertFrom-Json)
if(!$result.ok -or $result.codexExe -notmatch 'OpenAI\.Codex_.+\\app\\ChatGPT\.exe$'){
  throw '独立启动器未定位已安装的官方 Codex。'
}
if($result.profile -ne $profile -or (Test-Path -LiteralPath $profile) -ne $before){
  throw '只读检查修改了 Codex 配置目录。'
}
Write-Output 'PASS: independent Codex launcher resolves the Store app without changing profiles'
