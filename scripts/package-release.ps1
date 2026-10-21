param([string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($output -eq $source){throw 'Output directory cannot be the source root.'}
$manifest=Get-Content -LiteralPath (Join-Path $source 'package.json') -Raw -Encoding UTF8|ConvertFrom-Json
& node (Join-Path $PSScriptRoot 'check-repository.mjs')
if($LASTEXITCODE-ne 0){throw 'Repository checks failed; package was not created.'}
$files=@()
foreach($directory in @('.agents','.codex-plugin','.github','assets','docs','runtime','scripts','tests')){
  $files+=@(Get-ChildItem -LiteralPath (Join-Path $source $directory) -File -Recurse -Force)
}
foreach($name in @('.gitignore','.mcp.json','LICENSE','README.md','THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','SECURITY.md','CHANGELOG.md','package.json','Install.ps1','Uninstall.ps1','widget.ps1','widget.xaml','launch.vbs','supervisor.vbs','open-codex-wallpaper-hidden.vbs','Start-WallpaperExperiment.ps1','WALLPAPER_EXPERIMENT.md','DSH功能对照.md','安装GPT娘.cmd','打开GPT娘.cmd','停用GPT娘.cmd','打开Codex壁纸模式.cmd')){
  $files+=Get-Item -LiteralPath (Join-Path $source $name)
}
$relativeFiles=@()
foreach($file in ($files|Sort-Object FullName -Unique)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Links cannot be packaged.'}
  $relative=$file.FullName.Substring($source.TrimEnd('\').Length+1).Replace('\','/')
  if($relative -match '(^|/)(installation\.json|auth\.json|credentials\.json|\.env($|\.)|state|node_modules|\.git)(/|$)' -or $relative -match '\.(log|key|pem)$'){throw "Personal/generated file rejected: $relative"}
  $relativeFiles+=@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();full=$file.FullName}
}
$null=New-Item -ItemType Directory -Path $output -Force
$archive=Join-Path $output ('GPTPET-'+$manifest.version+'-source-candidate.zip')
if(Test-Path -LiteralPath $archive){throw 'Candidate already exists; choose a new output directory. Nothing was overwritten.'}
Add-Type -AssemblyName System.IO.Compression
$stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew)
try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
    foreach($file in $relativeFiles){
      $entry=$zip.CreateEntry(('GPTPET/'+$file.path),[IO.Compression.CompressionLevel]::Optimal)
      $entryStream=$entry.Open();$inputStream=[IO.File]::OpenRead($file.full)
      try{$inputStream.CopyTo($entryStream)}finally{$inputStream.Dispose();$entryStream.Dispose()}
    }
  }finally{$zip.Dispose()}
}finally{$stream.Dispose()}
$packageFiles=@($relativeFiles|ForEach-Object {@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})
$details=@{version=$manifest.version;status='unpublished-source-candidate';files=$packageFiles;assetScope='MIT code; inherited character assets have separate restrictions. See THIRD_PARTY_NOTICES.md.'}
[IO.File]::WriteAllText((Join-Path $output 'package-manifest.json'),($details|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'),($hash+'  '+[IO.Path]::GetFileName($archive)+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output ('Unpublished candidate: '+$archive)
Write-Output ('Files: '+$packageFiles.Count)
