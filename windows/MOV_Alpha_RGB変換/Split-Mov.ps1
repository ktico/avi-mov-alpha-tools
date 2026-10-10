param([string]$InputPath, [string]$OutputDirectory, [switch]$NoGui,
      [ValidateSet('Mov','Avi')][string]$InputKind = 'Mov', [switch]$AllowNoAlpha)
$ErrorActionPreference = 'Stop'
$formatName = $InputKind.ToUpperInvariant()
$activity = "$formatName → Alpha / RGB変換"
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'Conversion-Progress.ps1')
function Notify([string]$Message, [string]$Kind = 'Information') {
    if ($NoGui) { Write-Host $Message } else {
        [void][System.Windows.Forms.MessageBox]::Show($Message, $activity, 'OK', $Kind)
    }
}
function Find-Tool([string]$Name) {
    $local = Join-Path $PSScriptRoot "$Name.exe"
    if (Test-Path -LiteralPath $local) { return $local }
    $command = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "$Name.exe が見つかりません。FFmpegのbinフォルダをPATHに追加するか、このツールと同じフォルダにffmpeg.exeとffprobe.exeを置いてください。"
}
function Probe([string[]]$Arguments) {
    $result = & $script:ProbeExe @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'ファイル情報を取得できません。破損や対応していない形式の可能性があります。' }
    return (($result -join "`n") | ConvertFrom-Json)
}
$temporary = $null
try {
    $script:ProbeExe = Find-Tool 'ffprobe'
    $encoder = Find-Tool 'ffmpeg'
    if (-not $InputPath) {
        if ($NoGui) { throw 'InputPathを指定してください。' }
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $extension = $InputKind.ToLowerInvariant()
        $dialog.Title = "変換する${formatName}ファイルを選択"
        $dialog.Filter = "${formatName}ファイル (*.$extension)|*.$extension"
        if ($dialog.ShowDialog() -ne 'OK') { exit 0 }
        $InputPath = $dialog.FileName
        $dialog.Dispose()
    }
    $InputPath = (Resolve-Path -LiteralPath $InputPath).Path
    if ([IO.Path]::GetExtension($InputPath) -ine ('.' + $InputKind.ToLowerInvariant())) { throw "${formatName}ファイルを選択してください。" }
    $info = Probe @('-v','error','-select_streams','v:0','-show_entries','stream=pix_fmt,codec_name,width,height,duration:format=duration','-of','json','-i',$InputPath)
    if (@($info.streams).Count -eq 0) { throw '映像トラックがありません。' }
    $pixelFormat = $info.streams[0].pix_fmt
    $formats = Probe @('-v','error','-show_pixel_formats','-of','json')
    $descriptor = @($formats.pixel_formats | Where-Object { $_.name -eq $pixelFormat })
    $hasAlpha = $descriptor.Count -eq 1 -and $descriptor[0].flags.alpha -eq 1
    if (-not $hasAlpha) {
        if (-not $AllowNoAlpha) {
            if ($NoGui) { throw 'アルファがありません。承認して続ける場合は-AllowNoAlphaを指定してください。' }
            $warning = "アルファチャンネルを確認できませんでした（映像形式: $pixelFormat）。`n`n続けると、Alphaは白一色（すべて不透明）のマスク、RGBは通常の色の映像になります。`n透過の新規作成は行いません。変換を続けますか？"
            $answer = [System.Windows.Forms.MessageBox]::Show($warning, 'アルファチャンネルの警告', 'YesNo', 'Warning', 'Button2')
            if ($answer -ne 'Yes') { exit 0 }
        }
    }
    if (-not $OutputDirectory) { $OutputDirectory = [IO.Path]::GetDirectoryName($InputPath) }
    $OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $stem = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $alphaPath = Join-Path $OutputDirectory ($stem + '_Alpha.mp4')
    $rgbPath = Join-Path $OutputDirectory ($stem + '_RGB.mp4')
    if ((Test-Path -LiteralPath $alphaPath) -or (Test-Path -LiteralPath $rgbPath)) {
        throw "出力先に同名ファイルがあります。上書きせず終了しました。既存ファイルを移動するか、入力動画の名前を変更して再実行してください。`n$alphaPath`n$rgbPath"
    }
    $duration = 0.0
    [void][double]::TryParse([string]$info.format.duration, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration)
    $temporary = Join-Path $OutputDirectory ('.mov-split-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    $alphaTemp = Join-Path $temporary 'alpha.mp4'
    $rgbTemp = Join-Path $temporary 'rgb.mp4'
    $log = Join-Path $OutputDirectory ($stem + '_Alpha_RGB.log.txt')
    # 両方を同じデコード・タイムスタンプから作成し、同期を維持します。
    $alphaPreparation = ''
    $alphaPadColor = 'black'
    if (-not $hasAlpha) { $alphaPreparation = 'format=yuva444p,'; $alphaPadColor = 'white' }
    $filters = '[0:v:0]split=2[a][r];[a]' + $alphaPreparation + 'alphaextract,scale=in_range=full:out_range=full,pad=ceil(iw/2)*2:ceil(ih/2)*2:color=' + $alphaPadColor + ',format=yuv420p[alpha];[r]pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[rgb]'
    Write-Host "アルファチャンネル: $hasAlpha / $pixelFormat`n保存先:`n$alphaPath`n$rgbPath"
    Invoke-FfmpegProgress -Encoder $encoder -Duration $duration -Activity $activity -LogPath $log -NoGui:$NoGui -Arguments @('-n','-i',$InputPath,'-filter_complex',$filters,'-map','[alpha]','-an','-c:v','libx264','-preset','medium','-crf','0','-color_range','pc','-movflags','+faststart',$alphaTemp,'-map','[rgb]','-map','0:a?','-c:v','libx264','-preset','medium','-crf','18','-c:a','aac','-b:a','192k','-movflags','+faststart',$rgbTemp)
    foreach ($file in @($alphaTemp, $rgbTemp)) {
        $check = Probe @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name,width,height','-of','json','-i',$file)
        if ($check.streams[0].codec_name -ne 'h264') { throw '出力映像の確認に失敗しました。' }
    }
    [IO.File]::Move($alphaTemp, $alphaPath)
    try { [IO.File]::Move($rgbTemp, $rgbPath) } catch {
        [IO.File]::Move($alphaPath, $alphaTemp)
        throw
    }
    Notify "100 %：変換が完了しました。`n`n$alphaPath`n$rgbPath`n`nAlpha：白＝不透明、黒＝透明、灰色＝半透明`nRGB：色の映像と音声"
} catch {
    Notify $_.Exception.Message 'Error'
    exit 1
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}
