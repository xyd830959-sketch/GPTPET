function Open-QuoteEditor {
  if($script:quoteEditor -and $script:quoteEditor.IsVisible){$script:quoteEditor.Activate()|Out-Null;return}
  $editor=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="GPT 娘 · 我的语录" Width="540" Height="480" MinWidth="440" MinHeight="340" ShowInTaskbar="False"
 FontFamily="Microsoft YaHei UI" FontSize="14" Background="#FFFDF8" WindowStartupLocation="CenterScreen">
 <Grid Margin="22">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <TextBlock Margin="0,0,0,14" TextWrapping="Wrap" Foreground="#2F6A7B" Text="一行一句语录。想让某句更常出现，可写：3 | 这句语录。"/>
  <TextBox x:Name="Lines" Grid.Row="1" AcceptsReturn="True" AcceptsTab="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" FontSize="16" Padding="12" Background="White" BorderBrush="#D5E3E7"/>
  <TextBlock x:Name="Feedback" Grid.Row="2" Margin="0,12,0,10" Foreground="#2F6A7B" TextWrapping="Wrap"/>
  <Grid Grid.Row="3">
   <Button x:Name="Defaults" Content="恢复内置语录" Padding="12,6" HorizontalAlignment="Left"/>
   <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
    <Button x:Name="Save" Content="保存" Padding="20,6" Margin="0,0,10,0"/>
    <Button x:Name="Done" Content="关闭" Padding="20,6"/>
   </StackPanel>
  </Grid>
 </Grid>
</Window>
'@)
  $script:quoteEditor=$editor
  $editor.Owner=$script:window
  $lines=$editor.FindName('Lines');$feedback=$editor.FindName('Feedback')
  $current=Get-WidgetQuoteSettings $script:dataDir
  $lines.Text=($current.quotes|ForEach-Object{if($_.weight-eq 1){$_.text}else{([string]$_.weight)+' | '+$_.text}})-join [Environment]::NewLine
  $feedback.Text=if($current.error){$current.error}else{'每条最多 200 字。语录在你的电脑上保存。'}
  $editor.FindName('Save').Add_Click({
    try{
      $rows=@(foreach($line in ($script:quoteEditor.FindName('Lines').Text -split '\r?\n')){
        $text=$line.Trim();if(!$text){continue}
        if($text-match '^\s*(\d+(?:\.\d+)?)\s*\|\s*(.+)$'){@{text=$Matches[2].Trim();weight=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}}
        else{@{text=$text;weight=1}}
      })
      $saved=Save-WidgetQuotes $script:dataDir $rows
      $script:quoteEditor.FindName('Feedback').Text="已保存 $($saved.quotes.Count) 句。下一次点击气泡时就会使用。"
    }catch{$script:quoteEditor.FindName('Feedback').Text=$_.Exception.Message}
  })
  $editor.FindName('Defaults').Add_Click({
    try{
      $restored=Reset-WidgetQuotes $script:dataDir
      $script:quoteEditor.FindName('Lines').Text=($restored.quotes|ForEach-Object{$_.text})-join [Environment]::NewLine
      $script:quoteEditor.FindName('Feedback').Text='已恢复内置语录，你的旧列表已备份。'
    }catch{$script:quoteEditor.FindName('Feedback').Text=$_.Exception.Message}
  })
  $editor.FindName('Done').Add_Click({$script:quoteEditor.Close()})
  $editor.Add_KeyDown({param($sender,$event)if($event.Key-eq [Windows.Input.Key]::Escape){$sender.Close();$event.Handled=$true}})
  foreach($name in @('Save','Done','Defaults')){$editor.FindName($name).Style=$script:settingsMenuResources['SettingsPreset']}
  $editor.Show()
}

function Initialize-WidgetSettingsMenu {
  $themePath=Join-Path $script:appDir 'runtime\fox-menu-theme.xaml'
  $script:settingsMenuResources=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($themePath,[Text.Encoding]::UTF8))
  $script:settingsMenuSync=$false;$script:settingsMenuUi=@{};$script:settingsSubmenus=@()
  $script:context=New-Object Windows.Controls.ContextMenu
  $script:context.FontFamily=[Windows.Media.FontFamily]::new('Microsoft YaHei UI');$script:context.FontSize=14.5;$script:context.Width=328
  $script:context.MaxHeight=[Math]::Max(360,[Math]::Min(730,[Windows.SystemParameters]::WorkArea.Height-28))
  $script:context.Resources.MergedDictionaries.Add($script:settingsMenuResources)
  $script:context.Resources['SettingsSubmenuWidth']=[double]300
  $script:context.Resources['SettingsSubmenuMaxHeight']=[double]600
  $script:settingsMenuTarget=$script:context
  $script:context.Style=$script:settingsMenuResources['SettingsContext']
  $heading=[Windows.Markup.XamlReader]::Parse(@'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="8,7,4,11">
 <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
 <Border Width="38" Height="38" CornerRadius="11" Background="#ECF3F4" BorderBrush="#D8C5A0" BorderThickness="1" Margin="0,0,11,0">
  <Canvas Width="26" Height="26">
   <Path Data="M3,4 L9,8 Q13,6 17,8 L23,4 L22,16 Q20,23 13,24 Q6,23 4,16 Z" Fill="#FFFDF8" Stroke="#BC9964" StrokeThickness="1.2" StrokeLineJoin="Round"/>
   <Path Data="M6,13 Q9,20 13,21 Q17,20 20,13" Stroke="#D5E3E7" StrokeThickness="1"/>
   <Ellipse Canvas.Left="8" Canvas.Top="13" Width="2" Height="2" Fill="#2F6A7B"/><Ellipse Canvas.Left="16" Canvas.Top="13" Width="2" Height="2" Fill="#2F6A7B"/>
   <Path Data="M11,17 L15,17 L13,19 Z" Fill="#BC9964"/>
  </Canvas>
 </Border>
 <StackPanel Grid.Column="1" VerticalAlignment="Center">
  <TextBlock Text="狐娘" Foreground="#294B58" FontSize="18" FontWeight="SemiBold"/>
  <TextBlock Text="语录、外观、声音与壁纸" Foreground="#5E737D" FontSize="12" Margin="0,3,0,0"/>
 </StackPanel>
</Grid>
'@)
  Add-SettingsPanel $heading -Passive
  $script:settingsMenuUi.Actions=Add-SettingsSubmenu '动作' {
    $script:settingsMenuUi.ActionWave=Add-SettingsAction '挥手招呼' {$null=Invoke-ExtraCharacterAction 'wave'} -ReturnItem
    $script:settingsMenuUi.ActionLaugh=Add-SettingsAction '开心轻笑' {$null=Invoke-ExtraCharacterAction 'laugh'} -ReturnItem
    $script:settingsMenuUi.ActionYawn=Add-SettingsAction '困倦打哈欠' {$null=Invoke-ExtraCharacterAction 'yawn'} -ReturnItem
  } -ReturnItem
  $script:settingsMenuUi.Dialogue=Add-SettingsSubmenu '台词与提醒' {
  $script:settingsMenuUi.IdleTalk=Add-SettingsAction '待机闲聊' {param($sender,$event)$script:dialogueIdleEnabled=$sender.IsChecked;$script:dialogueNextIdle=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+(Get-Random -Minimum 120000 -Maximum 240001);Save-Settings} -Description '安静时每隔2～4分钟说一句' -Checkable -ReturnItem
  $script:settingsMenuUi.Completion=Add-SettingsAction '回复完成提醒' {param($sender,$event)$script:dialogueCompletionEnabled=$sender.IsChecked;if(!$script:dialogueCompletionEnabled){$script:dialoguePending=$null};Save-Settings} -Description '当前工作区的本地回复结束后提醒一次' -Checkable -ReturnItem
  Add-SettingsDivider
  $script:settingsMenuUi.QuoteEditor=Add-SettingsAction '编辑我的语录' {Open-QuoteEditor} -ReturnItem
  } -ReturnItem
  Add-SettingsDivider
  $script:settingsMenuUi.Appearance=Add-SettingsSubmenu '外观与位置' {
  $presets=New-Object Windows.Controls.Primitives.UniformGrid;$presets.Columns=3;$presets.Margin=[Windows.Thickness]::new(0,1,0,2);$script:settingsMenuUi.SizeButtons=@()
  foreach($choice in @(@{label='小 · 80%';scale=0.8},@{label='标准 · 100%';scale=1.0},@{label='大 · 140%';scale=1.4})){
    $button=New-Object Windows.Controls.Button;$button.Content=$choice.label;$button.Tag=$choice.scale;$button.Margin=[Windows.Thickness]::new(0,0,5,0);$button.Style=$script:settingsMenuResources['SettingsPreset'];$button.FontSize=12;$button.Padding=[Windows.Thickness]::new(5,6,5,6)
    $button.Add_Click({param($sender,$event)$script:sizeSlider.Value=[double]$sender.Tag;$event.Handled=$true})
    $presets.Children.Add($button)|Out-Null;$script:settingsMenuUi.SizeButtons+=,$button
  }
  Add-SettingsPanel $presets
  $size=New-SettingsSlider '挂件大小' 0.6 2.5 0.1
  $script:sizeSlider=$size.Slider;$script:settingsMenuUi.SizeText=$size.Value;$size.Slider.Value=$script:scale
  $size.Slider.Add_ValueChanged({param($sender,$event)if($script:settingsMenuSync){return};$script:scale=[Math]::Round($sender.Value,1);$script:settingsMenuUi.SizeText.Text=([Math]::Round($script:scale*100)).ToString()+'%';Update-WidgetSizePresets;Set-Appearance;Save-Settings})
  Add-SettingsPanel $size.Panel
  $script:settingsMenuUi.Hide=Add-SettingsAction '隐藏设置按钮' {param($sender,$event)$script:hideMenu=$sender.IsChecked;Set-MenuVisible $false;Save-Settings} -Description '仍可右键点角色打开设置' -Checkable -ReturnItem
  } -ReturnItem
  $script:settingsMenuUi.Colors=Add-SettingsSubmenu '配色效果' {
  $script:settingsMenuUi.ColorMixed=Add-SettingsAction '台词与颜色独立随机' {Set-WidgetColorMode 'mixed';Save-Settings;Update-WidgetSettingsMenu} -Description '先抽台词，再抽变色；每句都能触发' -Checkable -ReturnItem
  $script:settingsMenuUi.ColorOriginal=Add-SettingsAction '保持原色' {Set-WidgetColorMode 'original';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorPause=Add-SettingsAction '暂停颜色流动' {param($sender,$event)$script:colorPaused=$sender.IsChecked;Update-WidgetColorScene;Save-Settings} -Checkable -ReturnItem
  Add-SettingsDivider
  $chance=New-SettingsSlider '全挂件变色概率' 0 30 0.5
  $script:settingsMenuUi.ColorChance=$chance.Slider;$script:settingsMenuUi.ColorChanceText=$chance.Value;$chance.Slider.Value=$script:colorChance
  $chance.Slider.Add_ValueChanged({param($sender,$event)if($script:settingsMenuSync){return};$script:colorChance=[Math]::Round($sender.Value,1);$script:settingsMenuUi.ColorChanceText.Text=$script:colorChance.ToString()+'%';Save-Settings})
  Add-SettingsPanel $chance.Panel
  $textChance=New-SettingsSlider '仅台词变色概率' 0 30 0.5
  $script:settingsMenuUi.ColorTextChance=$textChance.Slider;$script:settingsMenuUi.ColorTextChanceText=$textChance.Value;$textChance.Slider.Value=$script:colorTextChance
  $textChance.Slider.Add_ValueChanged({param($sender,$event)if($script:settingsMenuSync){return};$script:colorTextChance=[Math]::Round($sender.Value,1);$script:settingsMenuUi.ColorTextChanceText.Text=$script:colorTextChance.ToString()+'%';Save-Settings})
  Add-SettingsPanel $textChance.Panel
  Add-SettingsSection '其他效果' -Divider
  $script:settingsMenuUi.ColorLinked=Add-SettingsAction '每句都随内容变色' {Set-WidgetColorMode 'linked';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorRainbow=Add-SettingsAction '一直流动彩虹' {Set-WidgetColorMode 'rainbow';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorRare=Add-SettingsAction '只偶尔全变色' {Set-WidgetColorMode 'rare';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorSurprise=Add-SettingsAction '偶尔变色＋指定台词' {Set-WidgetColorMode 'surprise';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorSpecial=Add-SettingsAction '只在指定台词出现时变色' {Set-WidgetColorMode 'special';Save-Settings;Update-WidgetSettingsMenu} -Checkable -ReturnItem
  $script:settingsMenuUi.ColorTriggerList=Add-SettingsAction '编辑指定台词名单' {Open-ColorTriggerEditor} -Description '独立随机模式不使用此名单' -ReturnItem
  } -ReturnItem
  # Retain controls only for internal maintenance; the normal menu has no entry.
  $script:context.Items.Remove($script:settingsMenuUi.Colors)
  $script:settingsSubmenus=@($script:settingsSubmenus|Where-Object{$_-ne $script:settingsMenuUi.Colors})
  $script:settingsMenuUi.Audio=Add-SettingsSubmenu '声音与点击' {
  $script:settingsMenuUi.Sound=Add-SettingsAction '动作音效' {param($sender,$event)$script:soundOn=$sender.IsChecked;if(!$script:soundOn){Stop-WidgetAudio};$script:settingsMenuUi.Volume.IsEnabled=$script:soundOn;Save-Settings} -Checkable -StayOpen -ReturnItem
  $volume=New-SettingsSlider '音量' 0 1 0.1
  $script:settingsMenuUi.Volume=$volume.Slider;$script:settingsMenuUi.VolumeText=$volume.Value;$volume.Slider.Value=$script:soundVolume
  $volume.Slider.Add_ValueChanged({param($sender,$event)if(!$script:settingsReady -or $script:settingsMenuSync -or !$script:context.IsOpen -or (!$sender.IsMouseCaptureWithin -and !$sender.IsKeyboardFocusWithin)){return};$script:soundVolume=[Math]::Round($sender.Value,2);$script:settingsMenuUi.VolumeText.Text=([Math]::Round($sender.Value*100)).ToString()+'%';Set-WidgetAudioVolume})
  $commitVolume={param($sender,$event)if(!$script:settingsReady -or $script:settingsMenuSync -or !$script:context.IsOpen){return};$script:soundVolume=[Math]::Round($script:settingsMenuUi.Volume.Value,2);$script:persistedSoundVolume=$script:soundVolume;$script:soundVolumeConfigured=$true;Save-Settings}
  $volume.Slider.Add_MouseLeftButtonUp($commitVolume)
  $volume.Slider.Add_KeyUp($commitVolume)
  Add-SettingsPanel $volume.Panel
  } -ReturnItem
  if($script:wallpaperModuleAvailable){try{Add-WallpaperSettingsMenu}catch{$script:wallpaperModuleAvailable=$false}}
  Add-SettingsDivider
  $exit=Add-SettingsAction '退出 GPT 娘' {Exit-WidgetForSession} -ReturnItem;$exit.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#8A685D')
  $script:context.Add_Opened({Update-WidgetSettingsMenu;Set-WidgetMenuBounds;Position-WidgetMenuToHost});Update-WidgetSettingsMenu;$script:window.ContextMenu=$script:context
}

function New-SettingsIcon([string]$Label) {
  $data=switch($Label){
    '动作' {'M8,1 L10,5.5 L15,6 L11.5,9.5 L12.5,15 L8,12 L3.5,15 L4.5,9.5 L1,6 L6,5.5 Z';break}
    '台词与提醒' {'M2,2 L14,2 L14,11 L7,11 L3,14 L3,11 L2,11 Z';break}
    '编辑我的语录' {'M3,11 L11,3 L13,5 L5,13 L2,14 Z M10,4 L12,6';break}
    '外观与位置' {'M3,3 L6,1 L10,1 L13,3 L15,6 L12,8 L12,15 L4,15 L4,8 L1,6 Z';break}
    '声音与点击' {'M2,6 L5,6 L9,3 L9,13 L5,10 L2,10 Z M12,5 Q16,8 12,11';break}
    'Codex 个性化' {'M2,3 L14,3 L14,13 L2,13 Z M2,11 L6,7 L10,11 L12,9 L14,11 M10,6 L11,6';break}
    '退出 GPT 娘' {'M8,1 L8,7 M4,3 A6,6 0 1 0 12,3';break}
    default {$null}
  }
  if(!$data){return $null}
  $icon=[Windows.Shapes.Path]::new();$icon.Data=[Windows.Media.Geometry]::Parse($data)
  $icon.Width=16;$icon.Height=16;$icon.Stretch=[Windows.Media.Stretch]::Uniform
  $icon.Stroke=[Windows.Media.BrushConverter]::new().ConvertFromString('#55808D');$icon.StrokeThickness=1.25
  $icon.StrokeStartLineCap='Round';$icon.StrokeEndLineCap='Round';$icon.StrokeLineJoin='Round'
  return $icon
}

function New-SettingsText([string]$Text,[double]$Size,[string]$Color){$t=New-Object Windows.Controls.TextBlock;$t.Text=$Text;$t.FontSize=$Size;$t.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($Color);return $t}
function Add-SettingsPanel($Panel,[switch]$Passive){
  $item=New-Object Windows.Controls.MenuItem;$item.Header=$Panel;$item.StaysOpenOnClick=$true;$item.Padding=[Windows.Thickness]::new(10,0,10,0);$item.Style=$script:settingsMenuResources['SettingsItem']
  if($Passive){$item.IsHitTestVisible=$false;$item.Focusable=$false};$script:settingsMenuTarget.Items.Add($item)|Out-Null
}
function Add-SettingsDivider{$line=New-Object Windows.Controls.Border;$line.Height=1;$line.Margin=[Windows.Thickness]::new(10,7,10,7);$line.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E7DDCA');Add-SettingsPanel $line -Passive}
function Add-SettingsSection([string]$Label,[switch]$Divider){if($Divider){Add-SettingsDivider};$t=New-SettingsText $Label 11.5 '#5E737D';$t.FontWeight=[Windows.FontWeights]::SemiBold;$t.Margin=[Windows.Thickness]::new(10,3,0,3);Add-SettingsPanel $t -Passive}
function Add-SettingsAction{
  param([string]$Label,[scriptblock]$Action,[string]$Description,[switch]$Checkable,[switch]$StayOpen,[switch]$ReturnItem)
  $item=New-Object Windows.Controls.MenuItem;$item.Style=$script:settingsMenuResources['SettingsItem'];$item.IsCheckable=[bool]$Checkable;$item.StaysOpenOnClick=[bool]$StayOpen
  if($Description){$p=New-Object Windows.Controls.StackPanel;$main=New-SettingsText $Label 14.5 '#294B58';$detail=New-SettingsText $Description 11.5 '#5E737D';$detail.Margin=[Windows.Thickness]::new(0,3,0,0);$p.Children.Add($main)|Out-Null;$p.Children.Add($detail)|Out-Null;$item.Header=$p}else{$item.Header=$Label}
  $item.Icon=New-SettingsIcon $Label
  $item.Add_Click($Action);$script:settingsMenuTarget.Items.Add($item)|Out-Null;if($ReturnItem){return $item}
}
function Add-SettingsSubmenu {
  param([string]$Label,[scriptblock]$Content,[switch]$ReturnItem)
  $item=New-Object Windows.Controls.MenuItem;$item.Header=$Label;$item.Style=$script:settingsMenuResources['SettingsItem'];$item.Tag=[Windows.Controls.Primitives.PlacementMode]::Right
  $item.Icon=New-SettingsIcon $Label
  $script:settingsMenuTarget.Items.Add($item)|Out-Null;$script:settingsSubmenus+=,$item
  $previous=$script:settingsMenuTarget;$script:settingsMenuTarget=$item
  try{& $Content}finally{$script:settingsMenuTarget=$previous}
  if($ReturnItem){return $item}
}
function New-SettingsSlider([string]$Label,[double]$Minimum,[double]$Maximum,[double]$Step){
  $panel=New-Object Windows.Controls.StackPanel;$panel.Margin=[Windows.Thickness]::new(0,6,0,2)
  $row=New-Object Windows.Controls.Grid;$row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))|Out-Null;$right=New-Object Windows.Controls.ColumnDefinition;$right.Width=[Windows.GridLength]::Auto;$row.ColumnDefinitions.Add($right)|Out-Null
  $caption=New-SettingsText $Label 12 '#5E737D';$value=New-SettingsText '' 12 '#2F6A7B';$value.FontWeight=[Windows.FontWeights]::SemiBold;[Windows.Controls.Grid]::SetColumn($value,1);$row.Children.Add($caption)|Out-Null;$row.Children.Add($value)|Out-Null
  $slider=New-Object Windows.Controls.Slider;$slider.Minimum=$Minimum;$slider.Maximum=$Maximum;$slider.TickFrequency=$Step;$slider.SmallChange=$Step;$slider.LargeChange=$Step;$slider.IsSnapToTickEnabled=$true;$slider.Style=$script:settingsMenuResources['SettingsSlider'];$slider.Margin=[Windows.Thickness]::new(0,2,0,0)
  $panel.Children.Add($row)|Out-Null;$panel.Children.Add($slider)|Out-Null;return @{Panel=$panel;Slider=$slider;Value=$value}
}
function Update-WidgetSizePresets{
  foreach($button in $script:settingsMenuUi.SizeButtons){$color=if([Math]::Abs([double]$button.Tag-$script:scale)-lt 0.05){'#DAEBEF'}else{'#EDF4F5'};$button.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($color)}
}
function Update-WidgetSettingsMenu{
  $script:settingsMenuSync=$true
  try{
    $script:settingsMenuUi.IdleTalk.IsChecked=$script:dialogueIdleEnabled;$script:settingsMenuUi.Completion.IsChecked=$script:dialogueCompletionEnabled;$script:settingsMenuUi.Sound.IsChecked=$script:soundOn;$script:settingsMenuUi.Hide.IsChecked=$script:hideMenu
    $script:settingsMenuUi.ColorLinked.IsChecked=$script:colorMode-eq 'linked';$script:settingsMenuUi.ColorRainbow.IsChecked=$script:colorMode-eq 'rainbow';$script:settingsMenuUi.ColorOriginal.IsChecked=$script:colorMode-eq 'original'
    $script:settingsMenuUi.ColorSurprise.IsChecked=$script:colorMode-eq 'surprise';$script:settingsMenuUi.ColorRare.IsChecked=$script:colorMode-eq 'rare';$script:settingsMenuUi.ColorSpecial.IsChecked=$script:colorMode-eq 'special'
    $script:settingsMenuUi.ColorMixed.IsChecked=$script:colorMode-eq 'mixed'
    $script:settingsMenuUi.ColorChance.Value=$script:colorChance;$script:settingsMenuUi.ColorChanceText.Text=$script:colorChance.ToString()+'%';$script:settingsMenuUi.ColorChance.IsEnabled=$script:colorMode-in @('rare','surprise','mixed')
    $script:settingsMenuUi.ColorTextChance.Value=$script:colorTextChance;$script:settingsMenuUi.ColorTextChanceText.Text=$script:colorTextChance.ToString()+'%';$script:settingsMenuUi.ColorTextChance.IsEnabled=$script:colorMode-eq 'mixed'
    $script:settingsMenuUi.ColorTriggerList.IsEnabled=$script:colorMode-in @('special','surprise')
    $script:settingsMenuUi.ColorPause.IsChecked=$script:colorPaused;$script:settingsMenuUi.ColorPause.IsEnabled=$script:colorMode-ne 'original'
    $script:settingsMenuUi.Volume.Value=$script:persistedSoundVolume;$script:settingsMenuUi.Volume.IsEnabled=$script:soundOn;$script:settingsMenuUi.VolumeText.Text=([Math]::Round($script:persistedSoundVolume*100)).ToString()+'%'
    $script:sizeSlider.Value=$script:scale;$script:settingsMenuUi.SizeText.Text=([Math]::Round($script:scale*100)).ToString()+'%';Update-WidgetSizePresets
    foreach($row in @(@('ActionWave','wave'),@('ActionLaugh','laugh'),@('ActionYawn','yawn'))){$script:settingsMenuUi[$row[0]].IsEnabled=($null-ne $script:characterPlayer -and $script:characterPlayer.HasAction($row[1]))}
    if($script:wallpaperModuleAvailable){try{Update-WallpaperSettingsMenu}catch{}}
  }finally{$script:settingsMenuSync=$false}
}

function Open-WidgetMenu {
  Set-WidgetMenuBounds
  Update-WidgetSettingsMenu
  $script:context.IsOpen=$true
  Position-WidgetMenuToHost
}

function Set-WidgetMenuBounds {
  $script:context.PlacementTarget=$script:ui.MenuButton
  $script:context.Placement=if($script:side-eq 'left'){[Windows.Controls.Primitives.PlacementMode]::Right}else{[Windows.Controls.Primitives.PlacementMode]::Left}
  $script:context.HorizontalOffset=if($script:side-eq 'left'){8}else{-8}
  $script:context.VerticalOffset=0
  foreach($submenu in $script:settingsSubmenus){$submenu.Tag=if($script:side-eq 'left'){[Windows.Controls.Primitives.PlacementMode]::Right}else{[Windows.Controls.Primitives.PlacementMode]::Left}}
  try{
    $frame=[System.Windows.Forms.Screen]::FromHandle($script:widgetHandle).WorkingArea
    $dpi=[GptWidgetNative]::GetDpiForWindow($script:widgetHandle)/96.0;if($dpi-le 0){$dpi=1}
    $script:context.Width=[Math]::Max(180,[Math]::Min(328,$frame.Width/$dpi-16))
    $script:context.MaxHeight=[Math]::Max(160,[Math]::Min(730,$frame.Height/$dpi-16))
    $script:context.Resources['SettingsSubmenuWidth']=[double][Math]::Max(180,[Math]::Min(300,$frame.Width/$dpi-16))
    $script:context.Resources['SettingsSubmenuMaxHeight']=[double][Math]::Max(160,[Math]::Min(600,$frame.Height/$dpi-16))
  }catch{}
}

function Position-WidgetMenuToHost {
  # Move only our own popup; host geometry is read-only.
  if(!$script:context.IsOpen){return}
  try{
    $script:context.UpdateLayout()
    $source=[Windows.Interop.HwndSource]::FromVisual($script:context)
    if(!$source -or $source.Handle-eq [IntPtr]::Zero){return}
    $frame=[System.Windows.Forms.Screen]::FromHandle($script:widgetHandle).WorkingArea;$menu=[GptWidgetNative]::Frame($source.Handle)
    $dpi=[GptWidgetNative]::GetDpiForWindow($script:widgetHandle)/96.0;if($dpi-le 0){$dpi=1}
    $margin=[int][Math]::Round(8*$dpi);$width=$menu.Right-$menu.Left;$height=$menu.Bottom-$menu.Top
    $origin=$script:ui.MenuButton.PointToScreen([Windows.Point]::new(0,0))
    $edge=$script:ui.MenuButton.PointToScreen([Windows.Point]::new($script:ui.MenuButton.ActualWidth,0))
    $desiredX=if($script:side-eq 'left'){$edge.X+$margin}else{$origin.X-$width-$margin}
    $x=[int][Math]::Round([Math]::Max($frame.Left+$margin,[Math]::Min($frame.Right-$width-$margin,$desiredX)))
    $y=[int][Math]::Round([Math]::Max($frame.Top+$margin,[Math]::Min($frame.Bottom-$height-$margin,$origin.Y)))
    if($menu.Left-ne $x -or $menu.Top-ne $y){[GptWidgetNative]::SetWindowPos($source.Handle,[IntPtr]::Zero,$x,$y,0,0,0x15)|Out-Null}
  }catch{}
}
