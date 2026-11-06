function script:Start-ExtraActionIntegrationChecks {
  $script:extraCheckPhase=0;$script:extraCheckStarted=[Diagnostics.Stopwatch]::StartNew();$script:extraCheckEvidence=@()
  $script:characterPlayer.Reset();$script:dialogueIdleEnabled=$false;$script:dialogueCompletionEnabled=$false
  Initialize-CharacterAudio $script:appDir
  $script:soundOn=$true;Set-WidgetAudioVolume 0.35
  foreach($audioPlayer in $script:characterAudio.Players.Values){$audioPlayer.IsMuted=$true}
  $script:extraNaturalEnds=@{wave=$false;laugh=$false;yawn=$false}
  $script:characterAudio.Players.wave.Add_MediaEnded({$script:extraNaturalEnds.wave=$true})
  $script:characterAudio.Players.laugh.Add_MediaEnded({$script:extraNaturalEnds.laugh=$true})
  $script:characterAudio.Players.yawn.Add_MediaEnded({$script:extraNaturalEnds.yawn=$true})
  $script:side='right';Set-Facing;Set-WidgetColorMode 'original'
  function script:Raise-ExtraAction([string]$Name){
    $item=switch($Name){'wave'{$script:settingsMenuUi.ActionWave};'laugh'{$script:settingsMenuUi.ActionLaugh};'yawn'{$script:settingsMenuUi.ActionYawn}}
    Assert-Integration ($script:settingsMenuUi.Actions.Items.Contains($item) -and $item.IsEnabled) 'Gesture is missing from the Actions menu.'
    $item.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  }
  $script:extraCheckTimer=[Windows.Threading.DispatcherTimer]::new();$script:extraCheckTimer.Interval=[TimeSpan]::FromMilliseconds(35)
  $script:extraCheckTimer.Add_Tick({
    try{
      if($script:extraCheckStarted.ElapsedMilliseconds-gt 25000){throw ('Extra gesture check timed out: '+$script:extraCheckPhase)}
      $player=$script:characterPlayer
      Assert-Integration (!$player.LastError -and !$player.LastAudioCallbackError) 'Extra gesture raised a player error.'
      switch($script:extraCheckPhase){
        0 {
          foreach($name in @('wave','laugh','yawn')){if(!$script:characterAudio.Opened[$name]){return}}
          foreach($name in @('wave','laugh','yawn')){Assert-Integration ($player.HasAction($name) -and $script:characterAudio.Available[$name]) 'A new gesture or voice did not initialize.'}
          Assert-Integration ($script:characterAudio.Played-eq 0) 'Extra voice autoplayed on initialization.'
          Assert-Integration ([Math]::Abs($script:characterAudio.Durations.wave-2.08)-lt .001 -and [Math]::Abs($script:characterAudio.Durations.laugh-1.36)-lt .001 -and [Math]::Abs($script:characterAudio.Durations.yawn-2.0)-lt .001) 'Selected crop duration mismatch.'
          $script:extraIdlePid=$player.DecoderProcessId
          Raise-ExtraAction 'wave';Assert-Integration ($player.State-eq 'wave') 'Wave menu did not start wave animation.'
          $script:extraCheckPhase=1
        }
        1 {
          if($script:characterAudio.Played-lt 1 -or $script:characterAudio.Players.wave.Position.TotalSeconds-lt 0.03){return}
          Assert-Integration ($script:characterAudio.LastCue-eq 'wave' -and $script:characterAudio.LastFrame-ge 24) 'Wave sound was not synchronized.'
          Raise-ExtraAction 'wave';Assert-Integration ($script:characterAudio.Played-eq 1) 'Duplicate wave stacked its sound.'
          Save-IntegrationFrame '8-wave-gesture'
          $script:extraCheckEvidence+=@{action='wave';cueFrame=$script:characterAudio.LastFrame;voiceSeconds=$script:characterAudio.Durations.wave}
          $script:extraCheckPhase=2
        }
        2 {
          if($player.State-ne 'idle'){return}
          Assert-Integration ($player.DecoderProcessId-eq $script:extraIdlePid) 'Wave did not reuse the existing idle decoder.'
          Assert-Integration (!$script:characterAudio.Active -and $script:extraNaturalEnds.wave) 'Wave was cut off before its natural end.'
          Raise-ExtraAction 'laugh';$script:extraCheckPhase=3
        }
        3 {
          if($script:characterAudio.Played-lt 2){return}
          Assert-Integration ($script:characterAudio.LastCue-eq 'laugh' -and $script:characterAudio.LastFrame-ge 21) 'Laugh voice was not synchronized.'
          Save-IntegrationFrame '9-laugh-gesture'
          $script:extraCheckEvidence+=@{action='laugh';cueFrame=$script:characterAudio.LastFrame;voiceSeconds=$script:characterAudio.Durations.laugh}
          $script:extraCheckPhase=4
        }
        4 {
          if($player.State-ne 'idle'){return}
          Assert-Integration (!$script:characterAudio.Active -and $script:extraNaturalEnds.laugh) 'Laugh was cut off before its natural end.'
          Raise-ExtraAction 'yawn';$script:extraCheckPhase=5
        }
        5 {
          if($script:characterAudio.Played-lt 3){return}
          Assert-Integration ($script:characterAudio.LastCue-eq 'yawn' -and $script:characterAudio.LastFrame-ge 24) 'Yawn voice was not synchronized.'
          Save-IntegrationFrame '10-yawn-gesture'
          $script:extraCheckEvidence+=@{action='yawn';cueFrame=$script:characterAudio.LastFrame;voiceSeconds=$script:characterAudio.Durations.yawn}
          $script:extraCheckPhase=6
        }
        6 {
          if($player.State-ne 'idle'){return}
          Assert-Integration (!$script:characterAudio.Active -and $script:extraNaturalEnds.yawn) 'Yawn was cut off before its natural end.'
          $script:soundOn=$false
          Raise-ExtraAction 'wave'
          Assert-Integration ($player.State-eq 'wave' -and $script:characterAudio.Played-eq 3) 'Muted gesture was not visual-only.'
          $null=$player.BeginDrag()
          Assert-Integration ($player.State-eq 'drag' -and !$script:characterAudio.Active) 'Drag failed to interrupt a gesture and its voice.'
          Assert-Integration (!(Invoke-ExtraCharacterAction 'laugh')) 'Menu gesture interrupted an active drag.'
          $player.EndDrag();$script:soundOn=$true
          Raise-ExtraAction 'yawn';$script:extraCheckPhase=7
        }
        7 {
          if($script:characterAudio.Played-lt 4){return}
          Assert-Integration ($script:characterAudio.Active) 'Yawn voice did not play on repeat after finishing.'
          $script:extraOwned=@($player.DecoderProcessId,$player.WarmIdleProcessId)|Where-Object{$_-gt 0}
          $script:window.Hide()
          Assert-Integration (!$script:characterAudio.Active -and !$player.DecoderActive) 'Hidden gesture retained audio or decoding.'
          $script:extraHiddenAt=$script:extraCheckStarted.ElapsedMilliseconds;$script:extraCheckPhase=8
        }
        8 {
          if($script:extraCheckStarted.ElapsedMilliseconds-$script:extraHiddenAt-lt 350){return}
          foreach($ownedPid in $script:extraOwned){Assert-Integration ($null-eq (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue)) 'An extra gesture decoder survived hiding.'}
          $bad=[GptPet.Animation.Clip]::new();$bad.Path=Join-Path $script:integrationOutput 'missing-gesture.webm';$bad.Prepared=$true;$bad.Loop=$false
          $rejected=$false;try{$player.RegisterAction('wave',$bad,24)}catch{$rejected=$true}
          Assert-Integration ($rejected -and $player.HasAction('wave')) 'Bad optional clip replaced a healthy gesture.'
          $report=@{passed=$true;waveSilent=$false;naturalEnds=$script:extraNaturalEnds;voices=$script:extraCheckEvidence;menuActionsVerified=3;audioPhysicallyMuted=$true;noAutoplay=$true;duplicateSuppressed=$true;returnsToIdle=$true;dragInterrupts=$true;hideCancels=$true;missingClipRejected=$true}
          [IO.File]::WriteAllText((Join-Path $script:integrationOutput 'extra-actions-result.json'),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
          Pass-Integration '7-extra-menu-actions-and-voices' 'Three actual menu commands; decoded transparent animation; voice cues at displayed frames; no autoplay/stacking; idle reuse; mute/drag/hide cancellation; missing clip isolation.'
          $script:extraCheckTimer.Stop()
          Finish-Integration $true
        }
      }
    }catch{$script:extraCheckTimer.Stop();Finish-Integration $false $_.Exception.ToString()}
  })
  $script:extraCheckTimer.Start()
}
