$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$app=Split-Path $PSScriptRoot -Parent
if(!$env:GPTPET_TEST_ROOT){throw 'An isolated test root is required.'}
$script:dataDir=Join-Path $env:GPTPET_TEST_ROOT 'features'
$null=[IO.Directory]::CreateDirectory($script:dataDir)
. (Join-Path $app 'runtime\quotes.ps1')
. (Join-Path $app 'runtime\audio.ps1')
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $app 'runtime\color-theme.ps1'),[Text.Encoding]::UTF8)))
$checks=0
function Assert-Feature([bool]$condition,[string]$label){if(!$condition){throw $label};$script:checks++}

$rows=@(ConvertTo-WidgetQuoteRows @(@{text='alpha';weight=2},@{text='alpha';weight=3},@{text='beta';weight=0},@{text=('x'*201);weight=1},@{text='gamma';weight='NaN'}))
Assert-Feature ($rows.Count -eq 1 -and $rows[0].weight -eq 5) 'Quote validation or duplicate weight aggregation failed.'
$rows=@(ConvertTo-WidgetQuoteRows @(@{text='Alpha';weight=600},@{text='alpha';weight=1},@{text=' Alpha ';weight=600},@{text='ALPHA';weight=2}))
Assert-Feature (($rows.text -join '|') -ceq 'Alpha|alpha|ALPHA') 'Quote identity must remain ordinal and preserve first-seen order.'
Assert-Feature ($rows[0].weight -eq 1000 -and $rows[1].weight -eq 1 -and $rows[2].weight -eq 2) 'Duplicate weights must retain their original cap and case distinction.'
$many=New-Object 'Collections.Generic.List[object]'
foreach($index in 1..1000){$many.Add(@{text=('quote-'+$index);weight=1})}
foreach($index in 1..1000){$many.Add(@{text=('quote-'+$index);weight=2})}
$rows=@(ConvertTo-WidgetQuoteRows $many.ToArray())
Assert-Feature ($rows.Count -eq 1000 -and $rows[0].text -eq 'quote-1' -and $rows[999].text -eq 'quote-1000' -and @($rows|Where-Object {$_.weight -ne 3}).Count -eq 0) 'Large quote batches changed order or weight totals.'
$saved=Save-WidgetQuotes $script:dataDir @(@{text='alpha';weight=2},@{text='beta';weight=1})
Assert-Feature ($saved.source -eq 'custom' -and $saved.quotes.Count -eq 2) 'Custom quotes were not persisted.'
$last=''
foreach($index in 1..20){$next=Get-WidgetQuote $script:dataDir;Assert-Feature ($next -ne $last) 'Consecutive quotes repeated.';$last=$next}
[IO.File]::WriteAllText((Join-Path $script:dataDir 'quotes.json'),'invalid json')
$fallback=Get-WidgetQuoteSettings $script:dataDir
Assert-Feature ($fallback.source -eq 'built-in' -and $fallback.quotes.Count -gt 1 -and !!$fallback.error) 'Invalid custom quotes did not fall back safely.'

foreach($name in @('press','release')){
  $duration=Get-WidgetWaveSeconds (Join-Path $app ('assets\'+$name+'.wav'))
  Assert-Feature ($duration -gt 0 -and $duration -lt 10) 'Bundled click sound has an invalid duration.'
}
foreach($case in @(@{value=[double]::NaN;expected=0.5},@{value=-1;expected=0},@{value=2;expected=1},@{value=0.25;expected=0.25})){
  $script:soundVolume=$case.value
  Assert-Feature ((Get-WidgetAudioVolume) -eq $case.expected) 'Audio volume validation failed.'
}
$script:soundOn=$false
Assert-Feature (!(Get-WidgetAudioEnabled)) 'Sound toggle was ignored.'
$script:soundOn=$true
Assert-Feature (Get-WidgetAudioEnabled) 'Sound enable was ignored.'

foreach($case in @(
  @{quota=$null;expired=$false;ink='#95889F';bar='#AA95CD'},
  @{quota=$null;expired=$true;ink='#95889F';bar='#AA95CD'},
  @{quota=@{used=0};expired=$true;ink='#95889F';bar='#B3A7C0'},
  @{quota=@{used=0};expired=$false;ink='#745A98';bar='#9B86C1'},
  @{quota=@{used=74.9};expired=$false;ink='#745A98';bar='#9B86C1'},
  @{quota=@{used=75};expired=$false;ink='#A06C1C';bar='#D0A051'},
  @{quota=@{used=89.9};expired=$false;ink='#A06C1C';bar='#D0A051'},
  @{quota=@{used=90};expired=$false;ink='#B74839';bar='#D77659'},
  @{quota=@{used=100};expired=$false;ink='#B74839';bar='#D77659'}
)){
  $palette=Get-WidgetQuotaPalette $case.quota $case.expired
  Assert-Feature ($palette.ink -ceq $case.ink -and $palette.bar -ceq $case.bar) 'Quota warning thresholds or semantic colours changed.'
}
$brush=Get-WidgetSolidBrush '#95889F'
Assert-Feature ($brush.IsFrozen -and $brush.Color.ToString() -eq '#FF95889F') 'Cached quota brush must be immutable and retain its colour.'
Assert-Feature ([object]::ReferenceEquals($brush,(Get-WidgetSolidBrush '#95889F'))) 'Repeated fixed colours allocate another brush.'

$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $app 'widget.xaml'),[Text.Encoding]::UTF8))
$script:ui=@{}
foreach($name in @('Root','Girl','BubbleShape','Tail','TailNear','Header','QuoteText','Refresh','MenuButton','ShortLeft','ShortBar','WeekLeft','WeekBar')){$script:ui[$name]=$script:window.FindName($name)}
$script:ui.Girl.Source=[Windows.Media.Imaging.BitmapImage]::new([Uri](Join-Path $app 'assets\gpt-dragon-niang-bust.png'))
$script:status=@{windows=@()};$script:collapsed=$false;$script:bubbleMode='quote';$script:colorMode='original'
$script:ui.QuoteText.Text='alpha';$script:ui.QuoteText.Tag='alpha'
try{
  Initialize-WidgetColors
  Assert-Feature (!$script:widgetColors.active) 'Original colour mode must stay inactive.'
  $script:colorMode='rainbow';Update-WidgetColorScene
  Assert-Feature ($script:widgetColors.active -and $script:widgetColors.halo.Visibility -eq [Windows.Visibility]::Visible) 'Rainbow colours were not applied.'
  $script:colorMode='original';Update-WidgetColorScene
  Assert-Feature (!$script:widgetColors.active -and $script:widgetColors.halo.Visibility -ne [Windows.Visibility]::Visible) 'Original colours were not restored.'
  $script:colorMode='mixed';$script:sceneRevision=1;$script:colorSceneKey='1|alpha';$script:colorSceneScope='text'
  Assert-Feature ((Get-WidgetColorScope 'alpha') -eq 'text') 'Independent text colour scope was lost.'
  $script:collapsed=$true
  Assert-Feature ((Get-WidgetColorScope 'alpha') -eq 'none') 'Collapsed quote retained colour scope.'
  $script:soundVolume=0.25
  Initialize-WidgetAudio $app
  Assert-Feature ($null -ne $script:gptNiangAudio -and !$script:gptNiangAudio.PendingRelease -and !$script:gptNiangAudio.Pressing) 'Audio initialization failed or started playback.'
  Stop-WidgetAudio
  Assert-Feature (!$script:gptNiangAudio.Timer.IsEnabled) 'Audio stop left its timer active.'
}finally{
  Stop-WidgetAudio
  if($script:gptNiangAudio){$script:gptNiangAudio.Press.Close();$script:gptNiangAudio.Release.Close()}
  $script:window.Close()
}
Write-Output ('PASS: quotes, silent audio initialization/volume and colour scope; '+$checks+' feature assertions')
