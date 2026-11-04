# Runs only when explicitly requested by the development verification launcher.
function Start-AnimationIntegrationCheck([string]$OutputDirectory){
  . (Join-Path $script:appDir 'runtime/dialogue-integration-check.ps1')
  . (Join-Path $script:appDir 'runtime/extra-actions-integration-check.ps1')
  $script:integrationOutput=[IO.Path]::GetFullPath($OutputDirectory)
  $null=[IO.Directory]::CreateDirectory($script:integrationOutput)
  $script:integrationResults=[Collections.Generic.List[object]]::new()
  $script:integrationClock=[Diagnostics.Stopwatch]::StartNew()
  $script:integrationPhase=0;$script:integrationPhaseAt=0L
  $script:integrationIdlePid=0;$script:integrationOwned=@()
  function script:Assert-Integration([bool]$Value,[string]$Message){if(!$Value){throw $Message}}
  function script:Pass-Integration([string]$Name,[string]$Evidence){
    $script:integrationResults.Add([pscustomobject]@{group=$Name;passed=$true;evidence=$Evidence})
  }
  function script:Save-IntegrationFrame([string]$Name){
    $script:window.UpdateLayout()
    $render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($script:window.ActualWidth),[int][Math]::Ceiling($script:window.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $render.Render($script:window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
    $stream=[IO.File]::Create((Join-Path $script:integrationOutput ($Name+'.png')))
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  function script:Raise-CharacterButton([bool]$Down){
    $event=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,[Environment]::TickCount,[Windows.Input.MouseButton]::Left)
    $event.RoutedEvent=if($Down){[Windows.UIElement]::MouseLeftButtonDownEvent}else{[Windows.UIElement]::MouseLeftButtonUpEvent}
    $script:ui.Girl.RaiseEvent($event)
  }
  function script:Raise-CharacterDrag {
    Raise-CharacterButton $true
    $script:drag.x-=12
    $event=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,[Environment]::TickCount)
    $event.RoutedEvent=[Windows.UIElement]::MouseMoveEvent
    $script:ui.Girl.RaiseEvent($event)
  }
  function script:Finish-Integration([bool]$Passed,[string]$ErrorMessage=''){
    $script:integrationTimer.Stop()
    $report=[ordered]@{passed=$Passed;error=$ErrorMessage;groups=@($script:integrationResults.ToArray());dataDir=$script:dataDir;appDir=$script:appDir;formalPluginModified=$false;checkedAt=[DateTimeOffset]::Now.ToString('o');audio=$script:integrationHealthyAudio;audioTestOutputMuted=$true}
    [IO.File]::WriteAllText((Join-Path $script:integrationOutput 'result.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $script:window.Close()
  }
  $script:integrationTimer=[Windows.Threading.DispatcherTimer]::new()
  $script:integrationTimer.Interval=[TimeSpan]::FromMilliseconds(50)
  $script:integrationTimer.Add_Tick({
    try{
      $elapsed=$script:integrationClock.ElapsedMilliseconds
      if($elapsed-gt 45000){throw ('Integration timed out in phase '+$script:integrationPhase)}
      $player=$script:characterPlayer
      Assert-Integration ($null-ne $player) 'Character player initialization failed.'
      Assert-Integration (!$player.LastError) ('Animation fallback: '+$player.LastError)
      switch($script:integrationPhase){
        0 {
          if(!$script:window.IsVisible -or $player.Status-ne 'Playing video: idle' -or !$script:status.ok -or !(Get-CharacterAudioState).ready){break}
          $health=$null
          try{$health=Get-Content -LiteralPath (Join-Path $script:dataDir 'worker-status.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
          $checkNow=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
          if(!$health -or [int]$health.parentPid-ne $PID -or $checkNow-[long]$health.at-lt 0 -or $checkNow-[long]$health.at-gt 5000){break}
          $worker=Get-Process -Id ([int]$health.pid) -ErrorAction SilentlyContinue
          if(!$worker){break}
          try{Assert-Integration ($worker.Path-eq $script:config.nodePath) 'Quota worker executable mismatch.'}finally{$worker.Dispose()}
          foreach($audioPlayer in $script:characterAudio.Players.Values){$audioPlayer.IsMuted=$true}
          $script:gptNiangAudio.Press.IsMuted=$true;$script:gptNiangAudio.Release.IsMuted=$true
          $script:soundOn=$true;$script:soundVolume=0.35;Set-WidgetAudioVolume
          Assert-Integration ($script:characterAudio.Played-eq 0) 'Audio played on initialization or idle.'
          Assert-Integration ($script:characterAudio.Durations.click-lt 0.55 -and $script:characterAudio.Durations.drag-le 0.65) 'Effects are too long.'
          Assert-Integration (@($script:status.windows).Count-ge 2) 'The real quota snapshot is incomplete.'
          Assert-Integration ($script:outsideClickWatcher.Installed) 'Outside menu listener was not installed.'
          Assert-Integration ($script:dataDir.StartsWith((Split-Path $script:appDir -Parent),[StringComparison]::OrdinalIgnoreCase)) 'Development data is not isolated.'
          $script:integrationIdlePid=$player.DecoderProcessId
          Show-Quota
          $script:integrationPhase=1;$script:integrationPhaseAt=$elapsed
        }
        1 {
          if($elapsed-$script:integrationPhaseAt-lt 750){break}
          Assert-Integration ($script:ui.ShortLeft.Text-match '\d+%' -and $script:ui.WeekLeft.Text-match '\d+%') 'Quota percentages did not render.'
          Assert-Integration ($script:ui.Girl.Source-is [Windows.Media.Imaging.WriteableBitmap]) 'The widget is not displaying decoded animation.'
          Save-IntegrationFrame '1-live-quota-idle'
          Pass-Integration '1-visible-widget-and-live-quota' 'Actual animation and quota; both PCM effects opened without autoplay; tests physically muted.'
          Hide-Quota
          Raise-CharacterButton $true;Raise-CharacterButton $false
          Assert-Integration ($script:bubbleMode-eq 'quota') 'First click did not show quota.'
          Raise-CharacterButton $true;Raise-CharacterButton $false
          Assert-Integration ($player.State-eq 'click') 'The actual click event did not trigger an animation.'
          Assert-Integration (!$script:collapsed -and $script:bubbleMode-eq 'quote') 'Click did not retain quota/quote behavior.'
          $script:integrationPhase=2;$script:integrationPhaseAt=$script:integrationClock.ElapsedMilliseconds
        }
        2 {
          if($elapsed-$script:integrationPhaseAt-lt 650){break}
          if($player.State-eq 'click' -and ($script:characterAudio.Played-lt 1 -or $script:characterAudio.Players.click.Position.TotalSeconds-lt 0.03)){break}
          Assert-Integration ($player.State-eq 'click' -and $script:ui.QuoteText.Text) 'Click or quote disappeared early.'
          Assert-Integration ($script:characterAudio.Played-eq 1 -and $script:characterAudio.LastCue-eq 'click' -and $script:characterAudio.LastFrame-eq 7) 'Click sound was not synchronized to displayed frame 7.'
          Invoke-CharacterSoundCue ([GptPet.Animation.CharacterSoundCue]::new('click',$script:characterAudio.LastSerial,66))
          Assert-Integration ($script:characterAudio.Played-eq 1) 'The same sound cue stacked.'
          $visual=@{collapsed=$script:collapsed;bubbleVisibility=[string]$script:ui.Bubble.Visibility;bubbleOpacity=$script:ui.Bubble.Opacity;sceneOpacity=$script:ui.SceneText.Opacity;quoteVisibility=[string]$script:ui.QuoteText.Visibility;quoteIsVisible=$script:ui.QuoteText.IsVisible;deadline=$script:sceneDeadline;now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();mode=$script:bubbleMode}
          [IO.File]::WriteAllText((Join-Path $script:integrationOutput 'quote-visual-state.json'),($visual|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
          Assert-Integration (!$script:collapsed -and $script:ui.Bubble.Opacity-gt 0.9 -and $script:ui.SceneText.Opacity-gt 0.9 -and $script:ui.QuoteText.IsVisible) 'Quote text exists but the bubble is not visibly rendered.'
          Assert-Integration ($script:ui.PressScale.ScaleX-eq 1 -and $script:ui.PressScale.ScaleY-eq 1) 'Legacy press scaling conflicts with video.'
          Save-IntegrationFrame '2-click-and-quote'
          $script:integrationPhase=3
        }
        3 {
          if($player.State-ne 'idle'){break}
          Assert-Integration ($player.DecoderProcessId-eq $script:integrationIdlePid) 'The widget did not reuse its idle decoder.'
          Pass-Integration '2-click-and-original-bubble' 'Actual click cue played at displayed frame 7; PCM position advanced; duplicates ignored; quote and idle reuse preserved.'
          Raise-CharacterDrag
          Assert-Integration ($player.State-eq 'drag' -and $script:drag.moved) 'Actual widget dragging did not trigger the squat.'
          $script:integrationPhase=4;$script:integrationPhaseAt=$elapsed
        }
        4 {
          if($player.Status-ne 'Playing video: drag-loop' -or $elapsed-$script:integrationPhaseAt-lt 2600){break}
          Assert-Integration ($script:characterAudio.Played-eq 2 -and $script:characterAudio.LastCue-eq 'drag' -and $script:characterAudio.LastFrame-eq 7) 'Drag sound was not played exactly once at displayed frame 7.'
          Save-IntegrationFrame '3-drag-crouch'
          $clock=[Diagnostics.Stopwatch]::StartNew();Raise-CharacterButton $false
          Assert-Integration ($player.State-eq 'idle' -and $clock.ElapsedMilliseconds-lt 500) 'Release did not restore idle immediately.'
          Assert-Integration (!$script:characterAudio.Active) 'Release did not immediately stop audio.'
          Assert-Integration ($null-eq $script:drag) 'The widget retained mouse drag state.'
          Pass-Integration '3-drag-squat-and-release' 'Drag cue at frame 7 plays once, never on loop repetition, and stops immediately on release.'
          Open-WidgetMenu
          Assert-Integration ($script:context.IsOpen -and $script:context.Items.Count-gt 5) 'Original settings menu did not open.'
          $script:context.IsOpen=$false
          Set-WidgetColorMode 'linked'
          Invoke-CharacterSoundCue ([GptPet.Animation.CharacterSoundCue]::new('drag',900,64))
          Stop-WidgetAudio
          Assert-Integration (!$script:characterAudio.Active) 'Existing stop/mute control did not stop the new audio.'
          $count=$script:characterAudio.Played;$script:soundOn=$false
          Invoke-CharacterSoundCue ([GptPet.Animation.CharacterSoundCue]::new('click',901,66))
          $script:soundOn=$true;Set-WidgetAudioVolume 0
          Invoke-CharacterSoundCue ([GptPet.Animation.CharacterSoundCue]::new('drag',902,64))
          Assert-Integration ($script:characterAudio.Played-eq $count) 'Muted or zero-volume action played audio.'
          Set-WidgetAudioVolume 0.23
          Assert-Integration ($script:characterAudio.Players.click.Volume-eq 0.23 -and $script:characterAudio.Players.drag.Volume-eq 0.23) 'The existing volume menu did not control both effects.'
          $script:side='left';Set-Facing
          $script:integrationPhase=5;$script:integrationPhaseAt=$elapsed
        }
        5 {
          if($elapsed-$script:integrationPhaseAt-lt 400){break}
          Assert-Integration ([object]::ReferenceEquals($script:widgetColors.tint.OpacityMask.ImageSource,$script:ui.Girl.Source)) 'Color mask uses an outdated image.'
          $body=$script:ui.Girl.TranslatePoint([Windows.Point]::new(104,104),$script:ui.Root)
          $empty=$script:ui.Girl.TranslatePoint([Windows.Point]::new(0,0),$script:ui.Root)
          Assert-Integration ((Test-GirlAlpha $body) -and !(Test-GirlAlpha $empty)) 'Mirrored transparent hit testing is incorrect.'
          Save-IntegrationFrame '4-theme-and-mirror'
          Pass-Integration '4-settings-theme-and-alpha' 'Original settings volume/stop/mute control both effects; zero volume suppresses cues; alpha and theme remain correct.'
          $script:integrationHealthyAudio=Get-CharacterAudioState
          Raise-CharacterDrag
          $script:integrationPhase=6;$script:integrationPhaseAt=$elapsed
        }
        6 {
          if($player.Status-ne 'Playing video: drag-enter' -or $player.PreloadedDragProcessId-le 0){break}
          $script:integrationOwned=@($player.DecoderProcessId,$player.WarmIdleProcessId,$player.PreloadedDragProcessId)|Where-Object {$_-gt 0}
          $script:timer.Stop();$script:hostEventTimer.Stop();$script:window.Hide()
          Assert-Integration (!$player.DecoderActive -and !$player.TimerRunning) 'Hidden widget is still decoding.'
          Assert-Integration (!$script:characterAudio.Active) 'Hidden widget retained audio.'
          $script:integrationPhase=7;$script:integrationPhaseAt=$elapsed
        }
        7 {
          if($elapsed-$script:integrationPhaseAt-lt 400){break}
          foreach($ownedPid in $script:integrationOwned){Assert-Integration ($null-eq (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue)) 'A hidden animation decoder survived.'}
          Assert-Integration ($script:characterAudio.Played-eq $script:integrationHealthyAudio.played) 'A canceled early drag later played a queued sound.'
          $fixture=Join-Path $script:integrationOutput 'bad-audio-fixture'
          $audioDir=Join-Path $fixture 'assets\action-audio';$null=[IO.Directory]::CreateDirectory($audioDir)
          [IO.File]::WriteAllText((Join-Path $audioDir 'click-pout-fast-v2.wav'),'Invalid local WAV test fixture.')
          Copy-Item -LiteralPath (Join-Path $script:appDir 'assets\action-audio\drag-flustered-soft-v4.wav') -Destination (Join-Path $audioDir 'drag-flustered-soft-v4.wav')
          Initialize-CharacterAudio $fixture
          Assert-Integration (!$script:characterAudio.Available.click -and $script:characterAudio.Available.drag -and $script:characterAudio.LastError) 'A damaged audio file was not isolated.'
          $baselinePath=Join-Path $script:integrationOutput 'protected-baseline.json'
          if(!(Test-Path -LiteralPath $baselinePath)){$baselinePath=Join-Path (Split-Path $script:appDir -Parent) 'protected-baseline.json'}
          $baseline=[IO.File]::ReadAllText($baselinePath)|ConvertFrom-Json
          foreach($entry in $baseline.PSObject.Properties){Assert-Integration ((Get-FileHash -LiteralPath $entry.Name).Hash-eq $entry.Value) ('Protected file changed: '+$entry.Name)}
          Pass-Integration '5-hide-cleanup-and-production-protection' 'Hide cancels audio and decoders; early drag never produces a late cue; corrupt WAV isolated; protected production hashes unchanged.'
          Invoke-DialogueIntegrationChecks
          $script:integrationTimer.Stop()
          Start-ExtraActionIntegrationChecks
        }
      }
    }catch{Finish-Integration $false $_.Exception.ToString()}
  })
  $script:integrationTimer.Start()
}
