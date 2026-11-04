function script:Invoke-DialogueIntegrationChecks {
  $script:window.Show();$script:context.IsOpen=$false;$script:drag=$null
  $script:dialogueLastActionAt=0;$script:dialogueLastAction='';$script:dialogueIdleEnabled=$true;$script:dialogueCompletionEnabled=$true
  Hide-Quota
  Click-Character
  Assert-Integration ($script:bubbleMode-eq 'quota') 'First click must show quota.'
  Click-Character
  Assert-Integration ($script:dialogueReason-eq 'click' -and $script:dialogueContexts.click-contains $script:ui.QuoteText.Tag) 'Click picked an unrelated dialogue.'
  $refreshClock=[Diagnostics.Stopwatch]::StartNew()
  for($i=0;$i-lt 100;$i++){
    $before=$script:ui.QuoteText.Tag
    Click-Character
    Assert-Integration ($script:ui.QuoteText.Tag-cne $before -and $script:bubbleMode-eq 'quote') 'A rapid click repeated text or showed quota.'
    Assert-Integration ($script:ui.SceneText.Opacity-eq 1 -and $script:ui.QuoteText.IsVisible -and (!$script:sceneTimer -or !$script:sceneTimer.IsEnabled)) 'Refresh used a delayed fade.'
    Assert-Integration ($script:sceneDeadline-$script:sceneStartedAt-eq 1500) 'Refresh lost 1.5-second timing.'
  }
  $refreshMs=$refreshClock.ElapsedMilliseconds
  Assert-Integration (!$script:settingsMenuUi.ContainsKey('Quote') -and !$script:settingsMenuUi.ContainsKey('Quota')) 'Removed menu actions still exist.'
  foreach($item in @($script:settingsMenuUi.IdleTalk,$script:settingsMenuUi.Completion,$script:settingsMenuUi.QuoteEditor)){Assert-Integration ($script:settingsMenuUi.Dialogue.Items.Contains($item)) 'Dialogue settings are not grouped.'}
  $null=Show-WidgetDialogue 'drag'
  Assert-Integration ($script:dialogueReason-eq 'drag' -and $script:dialogueContexts.drag-contains $script:ui.QuoteText.Tag) 'Drag did not pick shy dialogue.'
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $feed=@{at=$now;busy=$false;events=@(@{id=('fixture-'+[Guid]::NewGuid().ToString());at=$now;kind='reply-ready'})}
  Write-WidgetJson (Join-Path $script:dataDir 'completion-events.json') $feed
  $script:drag=@{moved=$true};Tick-WidgetDialogue $now
  Assert-Integration ($script:dialoguePending -and $script:dialogueReason-eq 'drag') 'Completion interrupted an active drag.'
  $script:drag=$null;Hide-Quota;Tick-WidgetDialogue ($now+1)
  Assert-Integration (!$script:collapsed -and $script:dialogueReason-eq 'complete' -and $script:dialogueContexts.complete-contains $script:ui.QuoteText.Tag) 'Queued completion reminder was not shown.'
  Set-BubbleState;Apply-Scene;Save-IntegrationFrame '6-completion-dialogue'
  Hide-Quota;Tick-WidgetDialogue ($now+2)
  Assert-Integration ($script:collapsed -and !$script:dialoguePending) 'The same completion was replayed.'
  $script:dialogueNextIdle=$now
  $script:context.IsOpen=$true;Tick-WidgetDialogue ($now+3)
  Assert-Integration $script:collapsed 'Idle dialogue interrupted the menu.'
  $script:context.IsOpen=$false
  # Hold the animation in an actual idle state before the idle-dialogue test.
  $script:characterPlayer.Reset()
  Tick-WidgetDialogue ($now+4)
  Assert-Integration (!$script:collapsed -and $script:dialogueReason-eq 'idle' -and $script:dialogueContexts.idle-contains $script:ui.QuoteText.Tag) 'Idle dialogue did not use the companion pool.'
  Set-BubbleState;Apply-Scene;Save-IntegrationFrame '7-idle-dialogue'
  Assert-Integration ($script:dialogueNextIdle-ge $now+120000 -and $script:dialogueNextIdle-le $now+240010) 'Idle interval is outside 2-4 minutes.'
  Click-Character
  Assert-Integration ($script:bubbleMode-eq 'quota') 'First click after idle chatter did not show quota.'
  Click-Character
  Assert-Integration ($script:bubbleMode-eq 'quote') 'Second click after idle chatter did not show dialogue.'
  Next-Bubble
  Assert-Integration $script:collapsed 'Bubble tap still cycles quota and dialogue.'
  Click-Character
  Assert-Integration ($script:bubbleMode-eq 'quota') 'Dismissal did not reset click sequence.'
  Hide-Quota
  $script:dialogueCompletionEnabled=$false
  $feed.events=@(@{id=('disabled-'+[Guid]::NewGuid().ToString());at=$now+5;kind='reply-ready'})
  Write-WidgetJson (Join-Path $script:dataDir 'completion-events.json') $feed
  $script:dialogueNextIdle=$now+200000;Tick-WidgetDialogue ($now+6)
  Assert-Integration ($script:collapsed -and !$script:dialoguePending) 'Disabled completion notification was shown.'
  $script:dialogueCompletionEnabled=$true;Tick-WidgetDialogue ($now+7)
  Assert-Integration ($script:collapsed -and !$script:dialoguePending) 'Re-enabling notifications replayed an ignored event.'
  $script:dialogueIdleEnabled=$false;$script:dialogueNextIdle=$now;Tick-WidgetDialogue ($now+8)
  Assert-Integration $script:collapsed 'Disabled idle chatter was shown.'
  $null=Show-WidgetDialogue 'manual';Tick-Scene ($script:sceneDeadline+1)
  Assert-Integration $script:collapsed 'Dialogue did not expire.'
  Pass-Integration '6-contextual-dialogue-policy' ('First click quota, subsequent clicks dialogue; 100 rapid refreshes without repeated adjacent text, cooldown or fade ('+$refreshMs+' ms); removed menu actions; grouped settings; 1.5-second timing; completion queues and deduplicates; idle gating; dismissal resets sequence.')
}
