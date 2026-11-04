# User-selected click and drag reactions, pre-opened without autoplay.
$script:characterAudio=$null
function Get-CharacterAudioState {
  if(!$script:characterAudio){return @{ready=$false;active=$false;played=0;lastError=''}}
  $audio=$script:characterAudio
  return @{ready=($audio.Opened.click -and $audio.Opened.drag);active=[bool]$audio.Active;files=$audio.Files;durations=$audio.Durations;
    played=$audio.Played;stopped=$audio.Stopped;lastCue=$audio.LastCue;lastFrame=$audio.LastFrame;lastSerial=$audio.LastSerial;
    revision='user-action-audio-20261104-v1';silentActions=@();extraOpened=$audio.Opened;extraErrors=$audio.Errors;lastError=$audio.LastError;enabled=(Get-WidgetAudioEnabled);volume=(Get-WidgetAudioVolume)}
}
function Stop-CharacterAudio {
  if(!$script:characterAudio){return}
  $audio=$script:characterAudio
  if($audio.Active){$audio.Stopped++}
  $audio.Active=$false
  foreach($player in $audio.Players.Values){try{$player.Stop();$player.Position=[TimeSpan]::Zero}catch{}}
}
function Close-CharacterAudio {
  if(!$script:characterAudio){return}
  Stop-CharacterAudio
  foreach($player in $script:characterAudio.Players.Values){try{$player.Close()}catch{}}
  $script:characterAudio=$null
}
function Set-CharacterAudioVolume {
  if(!$script:characterAudio){return}
  $volume=Get-WidgetAudioVolume
  foreach($player in $script:characterAudio.Players.Values){try{$player.Volume=$volume}catch{}}
  if($volume-le 0 -or !(Get-WidgetAudioEnabled)){Stop-CharacterAudio}
}
function Initialize-CharacterAudio([string]$AppDir){
  Close-CharacterAudio
  $script:characterAudio=@{Players=@{};Opened=@{};Available=@{};Durations=@{};Files=@{};Active=$false;Played=0;Stopped=0;LastKey='';LastCue='';LastFrame=-1;LastSerial=0;LastError='';Errors=@{}}
  $audio=$script:characterAudio
  $soundFiles=@{click='click-pout-fast-v2.wav';drag='drag-flustered-soft-v4.wav';wave='user-wave-20261104-v1.wav';laugh='user-laugh-20261104-v1.wav';yawn='user-yawn-20261104-v1.wav'}
  foreach($name in @('click','drag','wave','laugh','yawn')){
    try{
      $file=[IO.Path]::GetFullPath((Join-Path (Join-Path $AppDir 'assets/action-audio') $soundFiles[$name]))
      $audio.Files[$name]=$file
      $audio.Durations[$name]=Get-WidgetWaveSeconds $file
      $player=[Windows.Media.MediaPlayer]::new()
      $audio.Players[$name]=$player;$audio.Opened[$name]=$false;$audio.Available[$name]=$true
      $player.Add_MediaOpened({param($sender,$event)
        if(!$script:characterAudio){return}
        foreach($key in @('click','drag','wave','laugh','yawn')){
          if([object]::ReferenceEquals($script:characterAudio.Players[$key],$sender)){$script:characterAudio.Opened[$key]=$true}
        }
      })
      $player.Add_MediaEnded({param($sender,$event)
        $current=$script:characterAudio
        if(!$current -or !$current.Active){return}
        $name=$current.LastCue
        # WPF can report the end before the wall clock reaches the WAV duration.
        # Check the media position to reject stale events after a new playback.
        if([object]::ReferenceEquals($current.Players[$name],$sender) -and $sender.Position.TotalSeconds-ge $current.Durations[$name]-0.02){$current.Active=$false}
      })
      $player.Add_MediaFailed({param($sender,$event)
        $current=$script:characterAudio;if(!$current){return}
        foreach($key in @('click','drag','wave','laugh','yawn')){
          if([object]::ReferenceEquals($current.Players[$key],$sender)){
            $current.Opened[$key]=$false;$current.Available[$key]=$false
            $current.Errors[$key]='Audio unavailable: '+$key
            if($key-in @('click','drag')){$current.LastError=$current.Errors[$key]}
            if($current.LastCue-eq $key){$current.Active=$false}
          }
        }
      })
      $player.Volume=Get-WidgetAudioVolume
      $player.Open([Uri]$file)
    }catch{
      $audio.Available[$name]=$false;$audio.Opened[$name]=$false
      $audio.Errors[$name]='Audio unavailable: '+$name
      if($name-in @('click','drag')){$audio.LastError=$audio.Errors[$name]}
    }
  }
}
function Invoke-CharacterSoundCue($Cue){
  $audio=$script:characterAudio
  if(!$audio -or !(Get-WidgetAudioEnabled) -or (Get-WidgetAudioVolume)-le 0){return}
  $name=[string]$Cue.Action;$key=$name+':'+[string]$Cue.Serial
  # User-selected replacement wave sound restores this explicit menu action.
  if($name-notin @('click','drag','wave','laugh','yawn') -or $audio.LastKey-eq $key -or !$audio.Available[$name] -or !$audio.Opened[$name]){return}
  # No queue or delayed replay. A new cue replaces the current short effect.
  Stop-CharacterAudio
  $audio.LastKey=$key;$audio.LastCue=$name;$audio.LastFrame=[long]$Cue.Frame;$audio.LastSerial=[long]$Cue.Serial
  Set-CharacterAudioVolume
  try{
    $audio.Players[$name].Position=[TimeSpan]::Zero
    $audio.Players[$name].Play()
    $audio.Active=$true;$audio.Played++
  }catch{$audio.Active=$false;$audio.LastError='Audio playback failed: '+$name}
}
