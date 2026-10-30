$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $PSScriptRoot -Parent
if(!$env:GPTPET_TEST_ROOT){throw 'An isolated test root is required.'}
$script:dataDir=Join-Path $env:GPTPET_TEST_ROOT 'ui-menu'
$script:window=New-Object Windows.Window
$script:collapsed=$true
$script:bubbleMode='quota'
$script:scale=1.0
$script:soundOn=$true
$script:persistedSoundVolume=0.5
$script:colorMode='original'
$script:colorChance=0
$script:colorTextChance=0
$script:settingsReady=$false
. (Join-Path $script:appDir 'runtime\ui-settings.ps1')
. (Join-Path $script:appDir 'runtime\wallpaper-ui.ps1')
$script:wallpaperModuleAvailable=$true
try {
  Initialize-WidgetSettingsMenu
  foreach($state in @(@{collapsed=$true;mode='quota'},@{collapsed=$false;mode='quota'},@{collapsed=$false;mode='quote'})){
    $script:collapsed=$state.collapsed;$script:bubbleMode=$state.mode
    Update-WidgetSettingsMenu
    $labels=@($script:context.Items|Where-Object {$_.Header -is [string]}|ForEach-Object {$_.Header})
    $appearanceLabels=@($script:settingsMenuUi.Appearance.Items|Where-Object {$_.Header -is [string]}|ForEach-Object {$_.Header})
    if(@(($labels+$appearanceLabels)|Where-Object {$_ -in @('查看额度','收起额度气泡','刷新额度','恢复右下角位置')}).Count -or $script:settingsMenuUi.ContainsKey('Bubble')){throw 'Removed menu entries or their obsolete UI binding remain.'}
    foreach($label in @('换一句台词','编辑我的语录','外观与位置','声音与点击','Codex 个性化','退出 GPT 娘')){
      if($label -notin $labels){throw ('An unrelated menu entry was removed: '+$label)}
    }
    if(!$script:settingsMenuUi.Appearance.Items.Contains($script:settingsMenuUi.Hide) -or !$script:sizeSlider -or $script:settingsMenuUi.SizeButtons.Count -ne 3){throw 'Size or hide-button controls were removed from appearance settings.'}
  }
  # Exercise the remaining quote action: it must still open the bubble when collapsed.
  function Show-Quota {$script:quoteOpened=$true;$script:collapsed=$false}
  function Switch-Scene([string]$mode){$script:quoteSwitched=$mode}
  $script:collapsed=$true;$script:quoteOpened=$false;$script:quoteSwitched=$null
  $script:settingsMenuUi.Quote.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  if(!$script:quoteOpened -or $script:quoteSwitched -ne 'quote'){throw 'The remaining quote action no longer opens and switches the bubble.'}
  $script:collapsed=$true;$script:bubbleMode='quota'
  if(!$script:settingsMenuUi.Wallpaper){throw 'Codex personalization menu is missing.'}
  if(!$script:settingsMenuUi.WallpaperDimming -or $script:settingsMenuUi.WallpaperDimming.Value -ne 60){throw 'Wallpaper dimming slider should default to 60%.'}
  if($script:settingsMenuUi.WallpaperEnable.IsChecked){throw 'Wallpaper must be disabled by default.'}
  if($script:settingsMenuUi.WallpaperApply.IsEnabled){throw 'Apply must be disabled without an imported wallpaper.'}
  if(!$script:settingsMenuUi.WallpaperChoose -or $script:settingsMenuUi.WallpaperChoose.IsEnabled){throw 'Imported wallpaper chooser should exist and be disabled for an empty library.'}
  $emptyPicker=New-WallpaperPicker
  if($emptyPicker.FindName('Wallpapers').Items.Count -ne 0 -or $emptyPicker.FindName('Choose').IsEnabled){throw 'Empty picker allowed an invalid choice.'}
  $emptyPicker.Close()
  if(!$script:settingsMenuUi.Audio -or !$script:settingsMenuUi.Appearance){throw 'Existing settings menu items are missing.'}
  $messages=@{
    enable='壁纸功能已启用。'
    disable='壁纸功能已关闭，已恢复默认背景。'
    import='壁纸已导入。启用功能后可点击“应用壁纸”。'
    select='壁纸已选择，启用功能后可点击“应用壁纸”。'
    apply='壁纸样式已发送到 Codex 页面。请检查实际显示效果。'
    'set-dimming'='壁纸明暗已更新。'
    restore='已移除本模块注入的壁纸样式。'
  }
  foreach($command in $messages.Keys){
    if((Get-WallpaperActionMessage @{restored=$true} $command) -cne $messages[$command]){throw ('Wallpaper action message changed: '+$command)}
  }
  $warning=Get-WallpaperActionMessage @{warning='test warning'} 'apply'
  if($warning -cne ($messages.apply+' 部分页面未完成：test warning')){throw 'Partial wallpaper warning message changed.'}
  $warning=Get-WallpaperActionMessage @{warning='test warning'} 'set-dimming'
  if($warning -cne '明暗设置已保存，但当前页面未能更新：test warning'){throw 'Dimming warning message changed.'}
  if((Get-WallpaperActionMessage @{applied=$true} 'select') -cne '已切换到所选壁纸。'){throw 'Successful wallpaper selection was not reported.'}

  # Real WPF filename picker using isolated pictures; no personal data is touched.
  $images=Join-Path $script:dataDir 'codex-wallpaper\images'
  $null=[IO.Directory]::CreateDirectory($images)
  $ids=@('晴空.png','晚霞 [1].png','树林 & 海边.png',(('a'*64)+'.png'))
  $bytes=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRbkAAAAASUVORK5CYII=')
  foreach($id in $ids){[IO.File]::WriteAllBytes((Join-Path $images $id),$bytes)}
  [IO.File]::WriteAllText((Join-Path $images 'not-an-image.txt'),'unrelated fixture')
  $stateFile=Join-Path $script:dataDir 'codex-wallpaper\state.json'
  [IO.File]::WriteAllText($stateFile,(@{enabled=$false;selected=$ids[0];dimming=75}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  Update-WallpaperSettingsMenu
  if(!$script:settingsMenuUi.WallpaperChoose.IsEnabled){throw 'Chooser stayed disabled with imported images.'}
  $picker=New-WallpaperPicker
  $list=$picker.FindName('Wallpapers')
  if($list -isnot [Windows.Controls.ComboBox] -or $list.Items.Count -ne 4 -or $list.SelectedItem.Tag -ne $ids[0]){throw 'Filename dropdown did not retain the current choice or included unrelated files.'}
  foreach($item in $list.Items){if($item.Content -isnot [string] -or $item.Content -cne $item.Tag){throw 'Dropdown must show actual filenames with no preview content.'}}
  $exclusive=[IO.File]::Open((Join-Path $images $list.Items[0].Tag),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $exclusive.Dispose()
  $before=[IO.File]::ReadAllText($stateFile)
  $picker.Close()
  if([IO.File]::ReadAllText($stateFile) -cne $before){throw 'Closing the picker changed the selection.'}

  $factory=${function:New-WallpaperPicker};$invoke=${function:Invoke-WallpaperAction}
  try{
    $script:preparedPicker=New-WallpaperPicker
    $script:preparedPicker.WindowStartupLocation='Manual';$script:preparedPicker.Left=-10000;$script:preparedPicker.Top=-10000;$script:preparedPicker.ShowActivated=$false
    $script:targetWallpaperId=$ids[1]
    $script:preparedPicker.Add_ContentRendered({param($sender,$event)
      try{
        $render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($sender.ActualWidth),[int][Math]::Ceiling($sender.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $render.Render($sender);$png=New-Object Windows.Media.Imaging.PngBitmapEncoder;$png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
        $stream=[IO.File]::Create((Join-Path $env:GPTPET_TEST_ROOT 'wallpaper-picker.png'));try{$png.Save($stream)}finally{$stream.Dispose()}
        $items=$sender.FindName('Wallpapers')
        foreach($item in $items.Items){if($item.Tag -eq $script:targetWallpaperId){$items.SelectedItem=$item;break}}
        $sender.FindName('Choose').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      }catch{$script:pickerUiError=$_.Exception.Message;$sender.DialogResult=$false}
    })
    function New-WallpaperPicker {return $script:preparedPicker}
    function Invoke-WallpaperAction([string]$Command,[string]$ImagePath){$script:pickerRequest=@{command=$Command;id=$ImagePath}}
    Open-WallpaperPicker
    if($script:pickerUiError){throw $script:pickerUiError}
    if($script:pickerRequest.command -ne 'select' -or $script:pickerRequest.id -ne $ids[1]){throw 'Picker confirmation did not dispatch the selected imported ID.'}
    $script:preparedPicker=& $factory
    $script:preparedPicker.WindowStartupLocation='Manual';$script:preparedPicker.Left=-10000;$script:preparedPicker.Top=-10000;$script:preparedPicker.ShowActivated=$false
    $script:preparedPicker.Add_ContentRendered({param($sender,$event)$sender.DialogResult=$false})
    $script:pickerRequest=$null
    Open-WallpaperPicker
    if($script:pickerRequest -or [IO.File]::ReadAllText($stateFile) -cne $before){throw 'Cancelling the picker dispatched a change or altered saved settings.'}
  }finally{
    Set-Item -Path Function:New-WallpaperPicker -Value $factory
    Set-Item -Path Function:Invoke-WallpaperAction -Value $invoke
  }
  $importFactory=${function:New-WallpaperImportDialog};$invoke=${function:Invoke-WallpaperAction}
  $sourceImage=Join-Path $script:dataDir '待导入图片.png'
  [IO.File]::WriteAllBytes($sourceImage,$bytes)
  try{
    $script:preparedImport=New-WallpaperImportDialog $sourceImage
    if($script:preparedImport.FindName('FileName').Text -cne '待导入图片.png'){throw 'Save filename should default to the original picture filename.'}
    $script:preparedImport.WindowStartupLocation='Manual';$script:preparedImport.Left=-10000;$script:preparedImport.Top=-10000;$script:preparedImport.ShowActivated=$false
    $script:preparedImport.Add_ContentRendered({param($sender,$event)
      try{
        $input=$sender.FindName('FileName');$save=$sender.FindName('Save')
        $input.Text='../invalid';$save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if(!$sender.FindName('Error').Text -or $sender.Tag.Name){throw 'Invalid save filename was accepted.'}
        $input.Text='海边 & 晴空 [1].png'
        $sender.FindName('Error').Text=''
        $render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($sender.ActualWidth),[int][Math]::Ceiling($sender.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $render.Render($sender);$png=New-Object Windows.Media.Imaging.PngBitmapEncoder;$png.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
        $stream=[IO.File]::Create((Join-Path $env:GPTPET_TEST_ROOT 'wallpaper-save.png'));try{$png.Save($stream)}finally{$stream.Dispose()}
        $save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      }catch{$script:importUiError=$_.Exception.Message;$sender.DialogResult=$false}
    })
    function New-WallpaperImportDialog([string]$ImagePath){return $script:preparedImport}
    function Invoke-WallpaperAction([string]$Command,[string]$ImagePath,[string]$Name){$script:importRequest=@{command=$Command;path=$ImagePath;name=$Name}}
    Import-SelectedWallpaper $sourceImage
    if($script:importUiError){throw $script:importUiError}
    if($script:importRequest.command -cne 'import' -or $script:importRequest.path -cne $sourceImage -or $script:importRequest.name -cne '海边 & 晴空 [1].png'){throw 'Save confirmation did not dispatch the chosen actual filename.'}
    $script:preparedImport=& $importFactory $sourceImage
    $script:preparedImport.WindowStartupLocation='Manual';$script:preparedImport.Left=-10000;$script:preparedImport.Top=-10000;$script:preparedImport.ShowActivated=$false
    $script:preparedImport.Add_ContentRendered({param($sender,$event)$sender.DialogResult=$false})
    $script:importRequest=$null
    Import-SelectedWallpaper $sourceImage
    if($script:importRequest -or [IO.File]::ReadAllText($stateFile) -cne $before){throw 'Cancelling save dispatched an import or altered saved settings.'}
  }finally{
    Set-Item -Path Function:New-WallpaperImportDialog -Value $importFactory
    Set-Item -Path Function:Invoke-WallpaperAction -Value $invoke
  }
  $node=(Get-Command node -ErrorAction Stop).Source
  $module=Join-Path $script:appDir 'runtime\codex-wallpaper.mjs'
  $result=Join-Path $script:dataDir 'wallpaper-process-result.json'
  $null=New-Item -ItemType Directory -Path $script:dataDir -Force
  $arguments=Get-WallpaperProcessArguments $module 'status' $script:dataDir '' $result
  $process=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
  if($process.ExitCode -ne 0){throw 'Wallpaper background process failed.'}
  $reply=Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
  if(!$reply.ok -or $reply.enabled){throw 'Wallpaper background process returned an invalid or enabled state.'}
  $process.Dispose()
  # Exercise real Windows process argument transport with a Chinese filename and punctuation.
  $saveName='树荫 & 海岸 [1] $风景.png'
  $arguments=Get-WallpaperProcessArguments $module 'import' $script:dataDir $sourceImage $result $saveName
  $process=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
  try{
    if($process.ExitCode -ne 0){throw 'Named import process failed.'}
    $reply=Get-Content -LiteralPath $result -Raw -Encoding UTF8|ConvertFrom-Json
    if(!$reply.ok -or $reply.selected -cne $saveName){throw 'The actual saved filename did not survive process argument transport.'}
    if([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $images $saveName))) -cne [Convert]::ToBase64String($bytes)){throw 'Named import changed the image bytes.'}
    Update-WallpaperSettingsMenu
    $namedPicker=New-WallpaperPicker
    if($namedPicker.FindName('Wallpapers').SelectedItem.Content -cne $saveName){throw 'Newly saved filename is not selected in the dropdown.'}
    $namedPicker.Close()
  }finally{$process.Dispose()}
  # Exercise cancellation without opening dialogs or touching the live widget.
  $script:wallpaperProcess=Start-Process -FilePath $node -ArgumentList @('-e','"setInterval(()=>{},1000)"') -WindowStyle Hidden -PassThru
  $ownedPid=$script:wallpaperProcess.Id
  $script:wallpaperTimer=New-Object Windows.Threading.DispatcherTimer
  $script:wallpaperTimer.Start()
  $ownedTimer=$script:wallpaperTimer
  $script:wallpaperBusy=$true
  Stop-WallpaperAction
  Stop-WallpaperAction
  if($script:wallpaperBusy -or $script:wallpaperProcess -or $script:wallpaperTimer -or $ownedTimer.IsEnabled){throw 'Wallpaper cancellation did not release its process/timer or was not idempotent.'}
  # A kill is asynchronous; verify the OS process disappears within a bounded wait.
  $deadline=[DateTime]::UtcNow.AddSeconds(3)
  do {
    $running=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
    if(!$running){break}
    $running.Dispose();Start-Sleep -Milliseconds 50
  }while([DateTime]::UtcNow -lt $deadline)
  if($running){throw 'Wallpaper cancellation left its child running.'}
  Write-Output 'PASS: original settings and disabled wallpaper submenu coexist'
} finally { $script:window.Close() }
