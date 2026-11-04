# Explicit menu gestures. Existing click/drag routing and speech timing stay separate.
function Invoke-ExtraCharacterAction([string]$Name){
  if(!$script:characterPlayer -or !$script:window.IsVisible -or $script:drag){return $false}
  if(!$script:characterPlayer.PlayAction($Name)){return $false}
  Hide-Quota
  $script:dialogueClickSequence=$false
  $script:dialogueNextIdle=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+(Get-Random -Minimum 120000 -Maximum 240001)
  return $true
}
