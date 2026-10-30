function Read-WallpaperSettings {
  $file=Join-Path $script:dataDir 'codex-wallpaper\state.json'
  try {
    $state=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:wallpaperEnabled=($state.enabled -eq $true)
    $script:wallpaperSelected=if(Test-WallpaperFileName $state.selected){$state.selected}else{$null}
    $script:wallpaperDimming=if($state.dimming -is [int] -and $state.dimming -ge 20 -and $state.dimming -le 85){[int]$state.dimming}else{60}
  } catch {
    $script:wallpaperEnabled=$false;$script:wallpaperSelected=$null;$script:wallpaperDimming=60
  }
}

function Test-WallpaperFileName([string]$Name) {
  return $Name -and $Name.Length -le 200 -and $Name -ceq $Name.Trim() -and $Name -notmatch '[<>:"/\\|?*\x00-\x1f\x7f-\x9f]' -and $Name -match '^.+\.(png|jpe?g|webp)$' -and $Name -notmatch '[. ]\.(png|jpe?g|webp)$' -and $Name -notmatch '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'
}

function Get-ImportedWallpapers([switch]$FirstOnly) {
  $directory=Join-Path $script:dataDir 'codex-wallpaper\images'
  if(!(Test-Path -LiteralPath $directory -PathType Container)){return}
  $eligibleFiles={
    [IO.DirectoryInfo]::new($directory).EnumerateFiles() |
      Where-Object {(Test-WallpaperFileName $_.Name) -and $_.Length -gt 0 -and $_.Length -le 10MB -and !($_.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))}
  }
  if($FirstOnly){& $eligibleFiles | Select-Object -First 1}
  else{& $eligibleFiles | Sort-Object @{Expression='LastWriteTimeUtc';Descending=$true},Name}
}

function New-WallpaperPicker {
  Read-WallpaperSettings
  $dialog=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="选择已导入壁纸" Width="440" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterScreen"
 FontFamily="Microsoft YaHei UI" FontSize="14" Background="#FAF8FD">
 <Grid Margin="20">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <TextBlock x:Name="Hint" Margin="0,0,0,14" Foreground="#745A98" TextWrapping="Wrap"/>
  <ComboBox x:Name="Wallpapers" Grid.Row="1" Height="34" MaxDropDownHeight="240" IsEditable="False" IsTextSearchEnabled="True"/>
  <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
   <Button x:Name="Choose" Padding="18,7" Margin="0,0,10,0" IsDefault="True" IsEnabled="False"/>
   <Button Content="取消" Padding="18,7" IsCancel="True"/>
  </StackPanel>
 </Grid>
</Window>
'@)
  if($script:window -and $script:window.IsLoaded){$dialog.Owner=$script:window}
  $list=$dialog.FindName('Wallpapers');$choose=$dialog.FindName('Choose')
  $dialog.Tag=@{List=$list;Choose=$choose;SelectedId=$null}
  $choose.Content=if($script:wallpaperEnabled){'选择并应用'}else{'选择壁纸'}
  $files=@(Get-ImportedWallpapers)
  $dialog.FindName('Hint').Text=if(!$files.Count){'尚未导入壁纸，请先使用“导入本地壁纸”。'}elseif($script:wallpaperEnabled){'选择一张已导入的壁纸，确认后应用到 Codex。'}else{'选择一张已导入的壁纸；启用壁纸功能后可应用。'}
  foreach($file in $files){
    $item=New-Object Windows.Controls.ComboBoxItem;$item.Tag=$file.Name;$item.Content=$file.Name;$item.ToolTip=$file.Name
    $list.Items.Add($item)|Out-Null
    if($file.Name -ieq $script:wallpaperSelected){$list.SelectedItem=$item}
  }
  $choose.IsEnabled=$null -ne $list.SelectedItem
  $list.Tag=$dialog
  $list.Add_SelectionChanged({param($sender,$event)$sender.Tag.Tag.Choose.IsEnabled=$null -ne $sender.SelectedItem})
  $choose.Tag=$dialog
  $choose.Add_Click({param($sender,$event)
    $picker=$sender.Tag;$selected=$picker.Tag.List.SelectedItem
    if($selected){$picker.Tag.SelectedId=[string]$selected.Tag;$picker.DialogResult=$true}
  })
  return $dialog
}

function Open-WallpaperPicker {
  if($script:wallpaperBusy){return}
  try{
    $dialog=New-WallpaperPicker
    if($dialog.ShowDialog() -eq $true -and $dialog.Tag.SelectedId){Invoke-WallpaperAction 'select' $dialog.Tag.SelectedId}
  }catch{Show-WallpaperMessage $_.Exception.Message}
}

function New-WallpaperImportDialog([string]$ImagePath) {
  $dialog=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="保存壁纸" Width="440" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterScreen"
 FontFamily="Microsoft YaHei UI" FontSize="14" Background="#FAF8FD">
 <StackPanel Margin="20">
  <TextBlock Text="图片文件名" Foreground="#745A98" Margin="0,0,0,10"/>
  <TextBox x:Name="FileName" MaxLength="85" Padding="7"/>
  <TextBlock x:Name="Error" Foreground="#AF3550" TextWrapping="Wrap" Margin="0,6,0,0"/>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
   <Button x:Name="Save" Content="保存" Padding="18,7" Margin="0,0,10,0" IsDefault="True"/>
   <Button Content="取消" Padding="18,7" IsCancel="True"/>
  </StackPanel>
 </StackPanel>
</Window>
'@)
  if($script:window -and $script:window.IsLoaded){$dialog.Owner=$script:window}
  $input=$dialog.FindName('FileName');$input.Text=[IO.Path]::GetFileName($ImagePath)
  $extension=[IO.Path]::GetExtension($ImagePath)
  $dialog.Tag=@{Input=$input;Error=$dialog.FindName('Error');Name=$null;Extension=$extension}
  $dialog.FindName('Save').Tag=$dialog
  $dialog.FindName('Save').Add_Click({param($sender,$event)
    $form=$sender.Tag;$text=$form.Tag.Input.Text.Trim()
    $stem=$text -replace '\.(png|jpe?g|webp)$',''
    $name=$stem+$form.Tag.Extension
    if(!$stem -or $stem.Length -gt 80 -or !(Test-WallpaperFileName $name)){
      $form.Tag.Error.Text='请输入有效的文件名，名称不超过 80 个字符。';$form.Tag.Input.Focus()|Out-Null;return
    }
    $form.Tag.Name=$name;$form.DialogResult=$true
  })
  $dialog.Add_ContentRendered({param($sender,$event)$sender.Tag.Input.Focus()|Out-Null;$sender.Tag.Input.SelectAll()})
  return $dialog
}

function Import-SelectedWallpaper([string]$ImagePath) {
  if($script:wallpaperBusy){return}
  $dialog=New-WallpaperImportDialog $ImagePath
  if($dialog.ShowDialog() -eq $true){Invoke-WallpaperAction 'import' $ImagePath $dialog.Tag.Name}
}

function Update-WallpaperSettingsMenu {
  if(!$script:settingsMenuUi.Wallpaper){return}
  Read-WallpaperSettings
  $script:settingsMenuUi.WallpaperEnable.IsChecked=$script:wallpaperEnabled
  $script:settingsMenuUi.WallpaperApply.IsEnabled=$script:wallpaperEnabled -and !!$script:wallpaperSelected -and !$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperImport.IsEnabled=!$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperChoose.IsEnabled=!$script:wallpaperBusy -and $null -ne (Get-ImportedWallpapers -FirstOnly)
  $script:settingsMenuUi.WallpaperRestore.IsEnabled=!$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperEnable.IsEnabled=!$script:wallpaperBusy
  if($script:settingsMenuUi.WallpaperDimming){
    $script:settingsMenuUi.WallpaperDimming.Value=$script:wallpaperDimming
    $script:settingsMenuUi.WallpaperDimming.IsEnabled=!$script:wallpaperBusy
    $script:settingsMenuUi.WallpaperDimmingText.Text=$script:wallpaperDimming.ToString()+'%'
  }
  $script:settingsMenuUi.WallpaperName.Text=if($script:wallpaperSelected){'已选择本地壁纸'}else{'尚未导入壁纸'}
}

function Get-WallpaperProcessArguments([string]$Module,[string]$Command,[string]$DataDirectory,[string]$ImagePath,[string]$ResultFile,[string]$Name='') {
  $imageArgument=if($ImagePath){$ImagePath}else{'-'}
  $arguments=@($Module,$Command,$DataDirectory,$imageArgument,$ResultFile)
  if($Name){$arguments+=,[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Name))}
  return $arguments | ForEach-Object {'"'+($_ -replace '"','')+'"'}
}

function Stop-WallpaperAction {
  if($script:wallpaperTimer){$script:wallpaperTimer.Stop();$script:wallpaperTimer=$null}
  if($script:wallpaperProcess){
    try{if(!$script:wallpaperProcess.HasExited){$script:wallpaperProcess.Kill()}}catch{}
    try{$script:wallpaperProcess.Dispose()}catch{}
    $script:wallpaperProcess=$null
  }
  $script:wallpaperBusy=$false
}

function Get-WallpaperActionMessage($Result,[string]$Command){
  $message=switch($Command){
    'enable' {'壁纸功能已启用。'}
    'disable' {if($Result.restored){'壁纸功能已关闭，已恢复默认背景。'}else{'壁纸功能已关闭。当前 Codex 背景未能确认恢复；完全退出 Codex 后按普通方式重启即可清除会话样式。'}}
    'import' {'壁纸已导入。启用功能后可点击“应用壁纸”。'}
    'select' {if($Result.warning){'壁纸已选择，但当前页面未能完整更新：'+$Result.warning}elseif($Result.applied){'已切换到所选壁纸。'}else{'壁纸已选择，启用功能后可点击“应用壁纸”。'}}
    'apply' {'壁纸样式已发送到 Codex 页面。请检查实际显示效果。'}
    'set-dimming' {if($Result.warning){'明暗设置已保存，但当前页面未能更新：'+$Result.warning}else{'壁纸明暗已更新。'}}
    'restore' {'已移除本模块注入的壁纸样式。'}
  }
  if($Result.warning -and $Command -in @('apply','restore')){$message+=' 部分页面未完成：'+$Result.warning}
  return $message
}

function New-WallpaperNotice([string]$Message) {
  $notice=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="GPT 娘 · Codex 壁纸" Width="380" SizeToContent="Height" WindowStyle="None" ResizeMode="NoResize"
 AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" ShowActivated="False" Topmost="True" WindowStartupLocation="CenterScreen"
 FontFamily="Microsoft YaHei UI" FontSize="14">
 <Border Background="#FAF8FD" BorderBrush="#D7C9E5" BorderThickness="1" CornerRadius="10" Padding="18,14">
  <TextBlock x:Name="Message" Foreground="#554363" TextWrapping="Wrap"/>
 </Border>
</Window>
'@)
  $notice.FindName('Message').Text=$Message
  if($script:window -and $script:window.IsLoaded){$notice.Owner=$script:window}
  return $notice
}

function Show-WallpaperMessage([string]$Message,[switch]$AutoClose) {
  if($script:wallpaperNotice){$script:wallpaperNotice.Close()}
  if(!$AutoClose){[Windows.MessageBox]::Show($script:window,$Message,'GPT 娘 · Codex 壁纸')|Out-Null;return}
  $notice=New-WallpaperNotice $Message
  $timer=New-Object Windows.Threading.DispatcherTimer
  $timer.Interval=[TimeSpan]::FromMilliseconds(500)
  $notice.Tag=$timer
  $timer.Add_Tick(({param($sender,$event)$sender.Stop();$notice.Close()}.GetNewClosure()))
  $notice.Add_Closed({param($sender,$event)
    if($sender.Tag){$sender.Tag.Stop();$sender.Tag=$null}
    if([object]::ReferenceEquals($script:wallpaperNotice,$sender)){$script:wallpaperNotice=$null}
  })
  $script:wallpaperNotice=$notice
  try{$notice.Show();$timer.Start()}catch{$notice.Close();throw}
}

function Complete-WallpaperAction {
  if(!$script:wallpaperProcess -or !$script:wallpaperTimer){return}
  if(!$script:wallpaperProcess.HasExited -and $script:wallpaperStartedAt.Elapsed.TotalSeconds -lt 45){return}
  $script:wallpaperTimer.Stop()
  try {
    if(!$script:wallpaperProcess.HasExited){
      Stop-WallpaperAction
      throw '壁纸操作超时，已停止本次任务；可以重试。'
    }
    $result=Get-Content -LiteralPath $script:wallpaperResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if(!$result.ok){throw $result.error}
    $message=Get-WallpaperActionMessage $result $script:wallpaperCommand
    Show-WallpaperMessage $message -AutoClose:($script:wallpaperCommand -in @('import','select') -and !$result.warning)
  } catch {
    Show-WallpaperMessage $_.Exception.Message
  } finally {
    Stop-WallpaperAction
    Update-WallpaperSettingsMenu
  }
}

function Invoke-WallpaperAction([string]$Command,[string]$ImagePath='',[string]$Name='') {
  if($script:wallpaperBusy){return}
  try {
    $node=$script:config.nodePath
    if(!(Test-Path -LiteralPath $node)){throw 'Node.js 运行环境不可用。'}
    $module=Join-Path $script:appDir 'runtime\codex-wallpaper.mjs'
    if(!(Test-Path -LiteralPath $module)){throw '壁纸模块文件缺失。'}
    $resultDir=Join-Path $script:dataDir 'codex-wallpaper'
    $null=New-Item -ItemType Directory -Path $resultDir -Force
    $script:wallpaperResultFile=Join-Path $resultDir ('ui-result-'+[Guid]::NewGuid().ToString('N')+'.json')
    $script:wallpaperCommand=$Command
    $arguments=Get-WallpaperProcessArguments $module $Command $script:dataDir $ImagePath $script:wallpaperResultFile $Name
    $script:wallpaperProcess=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
    $script:wallpaperStartedAt=[Diagnostics.Stopwatch]::StartNew()
    $script:wallpaperBusy=$true
    Update-WallpaperSettingsMenu
    $script:wallpaperTimer=New-Object Windows.Threading.DispatcherTimer
    $script:wallpaperTimer.Interval=[TimeSpan]::FromMilliseconds(160)
    $script:wallpaperTimer.Add_Tick({Complete-WallpaperAction})
    $script:wallpaperTimer.Start()
  } catch {
    Stop-WallpaperAction
    Update-WallpaperSettingsMenu
    Show-WallpaperMessage $_.Exception.Message
  }
}

function Add-WallpaperSettingsMenu {
  $script:wallpaperBusy=$false
  Read-WallpaperSettings
  $script:settingsMenuUi.Wallpaper=Add-SettingsSubmenu 'Codex 个性化' {
    $script:settingsMenuUi.WallpaperEnable=Add-SettingsAction '启用壁纸功能' {
      param($sender,$event)
      Invoke-WallpaperAction $(if($sender.IsChecked){'enable'}else{'disable'})
    } -Description '默认关闭；启用后才会连接 Codex' -Checkable -ReturnItem
    $script:settingsMenuUi.WallpaperImport=Add-SettingsAction '导入本地壁纸' {
      try {
        $dialog=New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title='选择 Codex 壁纸'
        $dialog.Filter='图片 (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp'
        if($dialog.ShowDialog($script:window) -eq $true){Import-SelectedWallpaper $dialog.FileName}
      } catch {Show-WallpaperMessage $_.Exception.Message}
    } -ReturnItem
    $script:settingsMenuUi.WallpaperChoose=Add-SettingsAction '选择已导入壁纸' {Open-WallpaperPicker} -ReturnItem
    $script:settingsMenuUi.WallpaperApply=Add-SettingsAction '应用壁纸' {Invoke-WallpaperAction 'apply'} -ReturnItem
    $dimming=New-SettingsSlider '壁纸暗度（越大越暗）' 20 85 5
    $script:settingsMenuUi.WallpaperDimming=$dimming.Slider;$script:settingsMenuUi.WallpaperDimmingText=$dimming.Value
    $dimming.Slider.Value=$script:wallpaperDimming
    $dimming.Slider.Add_ValueChanged({param($sender,$event)$script:settingsMenuUi.WallpaperDimmingText.Text=([Math]::Round($sender.Value)).ToString()+'%'})
    $saveDimming={
      if($script:wallpaperBusy){return}
      $value=[int][Math]::Round($script:settingsMenuUi.WallpaperDimming.Value)
      if($value -ne $script:wallpaperDimming){Invoke-WallpaperAction 'set-dimming' ([string]$value)}
    }
    $dimming.Slider.Add_MouseLeftButtonUp($saveDimming)
    $dimming.Slider.Add_KeyUp($saveDimming)
    Add-SettingsPanel $dimming.Panel
    $script:settingsMenuUi.WallpaperRestore=Add-SettingsAction '恢复默认背景' {Invoke-WallpaperAction 'restore'} -ReturnItem
    $script:settingsMenuUi.WallpaperName=New-SettingsText '' 11.5 '#9685A8'
    Add-SettingsPanel $script:settingsMenuUi.WallpaperName -Passive
  } -ReturnItem
  Update-WallpaperSettingsMenu
}
