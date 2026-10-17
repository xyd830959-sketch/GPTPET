function Read-WallpaperSettings {
  $file=Join-Path $script:dataDir 'codex-wallpaper\state.json'
  try {
    $state=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:wallpaperEnabled=($state.enabled -eq $true)
    $script:wallpaperSelected=if($state.selected -match '^[a-f0-9]{64}\.(png|jpg|webp)$'){$state.selected}else{$null}
  } catch {
    $script:wallpaperEnabled=$false;$script:wallpaperSelected=$null
  }
}

function Update-WallpaperSettingsMenu {
  if(!$script:settingsMenuUi.Wallpaper){return}
  Read-WallpaperSettings
  $script:settingsMenuUi.WallpaperEnable.IsChecked=$script:wallpaperEnabled
  $script:settingsMenuUi.WallpaperApply.IsEnabled=$script:wallpaperEnabled -and !!$script:wallpaperSelected -and !$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperImport.IsEnabled=!$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperRestore.IsEnabled=!$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperEnable.IsEnabled=!$script:wallpaperBusy
  $script:settingsMenuUi.WallpaperName.Text=if($script:wallpaperSelected){'已选择本地壁纸'}else{'尚未导入壁纸'}
}

function Get-WallpaperProcessArguments([string]$Module,[string]$Command,[string]$DataDirectory,[string]$ImagePath,[string]$ResultFile) {
  $imageArgument=if($ImagePath){$ImagePath}else{'-'}
  return @($Module,$Command,$DataDirectory,$imageArgument,$ResultFile) | ForEach-Object {'"'+($_ -replace '"','')+'"'}
}

function Invoke-WallpaperAction([string]$Command,[string]$ImagePath='') {
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
    $arguments=Get-WallpaperProcessArguments $module $Command $script:dataDir $ImagePath $script:wallpaperResultFile
    $script:wallpaperProcess=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop
    $script:wallpaperBusy=$true
    Update-WallpaperSettingsMenu
    $script:wallpaperTimer=New-Object Windows.Threading.DispatcherTimer
    $script:wallpaperTimer.Interval=[TimeSpan]::FromMilliseconds(160)
    $script:wallpaperTimer.Add_Tick({
      if(!$script:wallpaperProcess.HasExited){return}
      $script:wallpaperTimer.Stop();$script:wallpaperBusy=$false
      try {
        $result=Get-Content -LiteralPath $script:wallpaperResultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if(!$result.ok){throw $result.error}
        $message=switch($script:wallpaperCommand){
          'enable' {'壁纸功能已启用。'}
          'disable' {if($result.restored){'壁纸功能已关闭，已恢复默认背景。'}else{'壁纸功能已关闭。当前 Codex 背景未能确认恢复；完全退出 Codex 后按普通方式重启即可清除会话样式。'}}
          'import' {'壁纸已导入。启用功能后可点击“应用壁纸”。'}
          'apply' {'壁纸样式已发送到 Codex 页面。请检查实际显示效果。'}
          'restore' {'已移除本模块注入的壁纸样式。'}
        }
        [Windows.MessageBox]::Show($script:window,$message,'GPT 娘 · Codex 壁纸')|Out-Null
      } catch {
        [Windows.MessageBox]::Show($script:window,$_.Exception.Message,'GPT 娘 · Codex 壁纸')|Out-Null
      } finally {
        Update-WallpaperSettingsMenu
      }
    })
    $script:wallpaperTimer.Start()
  } catch {
    $script:wallpaperBusy=$false
    Update-WallpaperSettingsMenu
    [Windows.MessageBox]::Show($script:window,$_.Exception.Message,'GPT 娘 · Codex 壁纸')|Out-Null
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
        if($dialog.ShowDialog($script:window) -eq $true){Invoke-WallpaperAction 'import' $dialog.FileName}
      } catch {[Windows.MessageBox]::Show($script:window,$_.Exception.Message,'GPT 娘 · Codex 壁纸')|Out-Null}
    } -ReturnItem
    $script:settingsMenuUi.WallpaperApply=Add-SettingsAction '应用壁纸' {Invoke-WallpaperAction 'apply'} -ReturnItem
    $script:settingsMenuUi.WallpaperRestore=Add-SettingsAction '恢复默认背景' {Invoke-WallpaperAction 'restore'} -ReturnItem
    $script:settingsMenuUi.WallpaperName=New-SettingsText '' 11.5 '#9685A8'
    Add-SettingsPanel $script:settingsMenuUi.WallpaperName -Passive
  } -ReturnItem
  Update-WallpaperSettingsMenu
}
