# Contextual dialogue; all UI work stays on the widget dispatcher.
function Initialize-WidgetDialogue {
  $script:dialogueContexts=([IO.File]::ReadAllText((Join-Path $script:appDir 'assets/dialogue-contexts.json'))|ConvertFrom-Json).contexts
  $script:dialogueHistory=@{};$script:dialogueClickSequence=$false
  $script:dialogueReason='none';$script:dialogueLastAction='';$script:dialogueLastActionAt=0L
  $script:dialogueNextIdle=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+(Get-Random -Minimum 120000 -Maximum 240001)
  $script:dialogueSeen=@{};$script:dialoguePending=$null
  $script:dialogueStartedAt=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $script:dialogueRevision='quota-first-click-v2'
}
function Get-ContextDialogue([string]$Context){
  $settings=Get-WidgetQuoteSettings $script:dataDir
  if($Context-eq 'complete'){
    $rows=@($script:dialogueContexts.complete|ForEach-Object{[pscustomobject]@{text=[string]$_;weight=1.0}})
  }else{
    $rows=@($settings.quotes)
    if($Context-ne 'manual'){
      $allowed=@($script:dialogueContexts.$Context)
      $filtered=@($rows|Where-Object{$allowed-contains $_.text})
      if($filtered.Count){$rows=$filtered}
      else{
        # Custom editor lines have no action metadata; use the matching built-in pool.
        $rows=@($allowed|ForEach-Object{[pscustomobject]@{text=[string]$_;weight=1.0}})
      }
    }
  }
  if(!$rows.Count){return Get-WidgetQuote $script:dataDir}
  $history=@($script:dialogueHistory[$Context])
  $keep=[Math]::Min(8,[Math]::Max(0,$rows.Count-1))
  if($history.Count-gt $keep){$history=@($history|Select-Object -Last $keep)}
  $lastShown=[string]$script:ui.QuoteText.Tag
  $choices=@($rows|Where-Object{$history-notcontains $_.text -and $_.text-cne $lastShown})
  if(!$choices.Count){$choices=@($rows|Where-Object{$_.text-cne $lastShown})}
  if(!$choices.Count -and $Context-eq 'click'){$choices=@($script:dialogueContexts.click|Where-Object{$_-cne $lastShown}|ForEach-Object{[pscustomobject]@{text=[string]$_;weight=1.0}})}
  if(!$choices.Count){$choices=$rows}
  $total=0.0;foreach($row in $choices){$total+=$row.weight}
  $draw=$script:widgetQuoteRandom.NextDouble()*$total;$selected=$choices[-1]
  foreach($row in $choices){$draw-=$row.weight;if($draw-lt 0){$selected=$row;break}}
  $script:dialogueHistory[$Context]=@($history)+@($selected.text)
  [string]$selected.text
}
function Show-WidgetDialogue([string]$Context='manual',[long]$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
  if($Context-in @('click','drag')){
    $script:dialogueNextIdle=$Now+(Get-Random -Minimum 120000 -Maximum 240001)
    $script:dialogueLastAction=$Context;$script:dialogueLastActionAt=$Now
  }
  if($Context-ne 'click'){$script:dialogueClickSequence=$false}
  $script:dialogueReason=$Context
  Show-Quota 'quote' $Context
  return $true
}
function Tick-WidgetDialogue([long]$Now){
  try{
    $eventsPath=Join-Path $script:dataDir 'completion-events.json'
    if([IO.File]::Exists($eventsPath)){
      $feed=[IO.File]::ReadAllText($eventsPath)|ConvertFrom-Json
      foreach($event in @($feed.events)){
        if(!$event.id -or $script:dialogueSeen.ContainsKey([string]$event.id)){continue}
        $script:dialogueSeen[[string]$event.id]=$Now
        if($script:dialogueCompletionEnabled -and [long]$event.at-ge $script:dialogueStartedAt -and $Now-[long]$event.at-le 120000 -and [long]$event.at-le $Now+2000){
          $script:dialoguePending=@{at=[long]$event.at;id=[string]$event.id}
        }
      }
      if($script:dialogueSeen.Count-gt 100){
        foreach($key in @($script:dialogueSeen.Keys)){if($Now-$script:dialogueSeen[$key]-gt 300000){$script:dialogueSeen.Remove($key)}}
      }
    }
  }catch{} # Missing or transiently locked local event files do not interrupt the pet.
  if(!$script:dialogueCompletionEnabled){$script:dialoguePending=$null}
  if($script:dialoguePending -and $Now-$script:dialoguePending.at-gt 120000){$script:dialoguePending=$null}
  $blocked=(!$script:window.IsVisible -or $script:drag -or $script:context.IsOpen -or ($script:quoteEditor -and $script:quoteEditor.IsVisible) -or $script:wallpaperBusy -or !$script:collapsed)
  if($blocked){return}
  if($script:dialoguePending){
    $null=Show-WidgetDialogue 'complete' $Now
    $script:dialoguePending=$null
    $script:dialogueNextIdle=$Now+(Get-Random -Minimum 120000 -Maximum 240001)
    return
  }
  if($script:dialogueIdleEnabled -and $Now-ge $script:dialogueNextIdle){
    # Work in progress and animation transitions postpone casual chatter.
    if(($feed -and [bool]$feed.busy -and $Now-[long]$feed.at-lt 10000) -or ($script:characterPlayer -and $script:characterPlayer.State-ne 'idle')){return}
    $null=Show-WidgetDialogue 'idle' $Now
    $script:dialogueNextIdle=$Now+(Get-Random -Minimum 120000 -Maximum 240001)
  }
}
