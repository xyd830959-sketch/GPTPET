$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
if (!('GptPet.Animation.CharacterPlayer' -as [type])) {
    $refs = @(
        [Windows.Controls.Image].Assembly.Location,
        [Windows.Media.ImageBrush].Assembly.Location,
        [Windows.Threading.Dispatcher].Assembly.Location,
        'System.dll', 'System.Core.dll', 'System.Xaml.dll'
    )
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'CharacterPlayer.cs'))) -ReferencedAssemblies $refs
}

function Resolve-CharacterAsset([string]$Root, [string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'Character assets must use relative paths.'
    }
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (!$resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Character asset path leaves the manifest directory.'
    }
    return $resolved
}

function New-CharacterPlayer {
    param(
        [Parameter(Mandatory=$true)][Windows.Controls.Image]$Image,
        [Parameter(Mandatory=$true)][string]$ManifestPath,
        [string]$FfmpegPath
    )
    $file = [IO.Path]::GetFullPath($ManifestPath)
    $root = [IO.Path]::GetDirectoryName($file)
    $manifest = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1) { throw 'Unsupported character manifest version.' }
    $stills = foreach ($name in @('idle','click','drag')) {
        $path = Resolve-CharacterAsset $root $manifest.stills.$name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing static character image: $name" }
        $path
    }
    $clips = foreach ($name in @('idle','click','dragEnter','dragLoop')) {
        $item = $manifest.clips.$name
        if ($null -eq $item -or $item.prepared -isnot [bool]) { throw "Invalid clip entry: $name" }
        $clip = [GptPet.Animation.Clip]::new()
        $clip.Path = Resolve-CharacterAsset $root $item.path
        if ([IO.Path]::GetExtension($clip.Path) -ine '.webm') { throw 'Video clips must be prepared WebM files.' }
        $clip.Prepared = $item.prepared
        $clip.Loop = $name -in @('idle','dragLoop')
        $clip
    }
    if ($FfmpegPath) {
        $FfmpegPath = [IO.Path]::GetFullPath($FfmpegPath)
        if (!(Test-Path -LiteralPath $FfmpegPath -PathType Leaf)) { throw 'Explicit FFmpeg executable does not exist.' }
    }
    $player = [GptPet.Animation.CharacterPlayer]::new(
        $Image, $stills[0], $stills[1], $stills[2],
        $clips[0], $clips[1], $clips[2], $clips[3], $FfmpegPath,
        [int]$manifest.playback.width, [int]$manifest.playback.height,
        [int]$manifest.playback.fps, [int]$manifest.playback.staticClickMs,
        [int]$manifest.anchors.idleFootY, [int]$manifest.anchors.clickFootY,
        [int]$manifest.anchors.dragFootY, [int]$manifest.anchors.targetFootY
    )
    if ($null -ne $manifest.playback.transitionMs) { $player.TransitionMs = [int]$manifest.playback.transitionMs }
    if ($null -ne $manifest.clips.dragExit) {
        $returnItem = $manifest.clips.dragExit
        $returnPath = Resolve-CharacterAsset $root $returnItem.path
        if ($returnItem.prepared -isnot [bool] -or [IO.Path]::GetExtension($returnPath) -ine '.webm' -or !(Test-Path -LiteralPath $returnPath -PathType Leaf)) {
            $player.Dispose(); throw 'Invalid drag return clip.'
        }
        $returnClip = [GptPet.Animation.Clip]::new()
        $returnClip.Path = $returnPath; $returnClip.Prepared = $returnItem.prepared; $returnClip.Loop = $false
        $player.DragReturn = $returnClip
    }
    $script:extraActionLoadErrors=@{}
    if($manifest.actions){
      foreach($entry in $manifest.actions.PSObject.Properties){
        if($entry.Name-notin @('wave','laugh','yawn')){continue}
        try{
          $item=$entry.Value;$path=Resolve-CharacterAsset $root $item.path
          if($item.prepared -isnot [bool] -or !$item.prepared -or [IO.Path]::GetExtension($path)-ine '.webm'){throw 'Invalid extra clip entry.'}
          $clip=[GptPet.Animation.Clip]::new();$clip.Path=$path;$clip.Prepared=$true;$clip.Loop=$false
          $player.RegisterAction($entry.Name,$clip,[int]$item.cueFrame)
        }catch{$script:extraActionLoadErrors[$entry.Name]=$_.Exception.Message}
      }
    }
    return $player
}
