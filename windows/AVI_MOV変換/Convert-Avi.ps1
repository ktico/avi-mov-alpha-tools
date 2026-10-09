param([string]$InputPath, [string]$OutputPath, [switch]$AllowNoAlpha, [switch]$NoGui)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'Conversion-Progress.ps1')
function Notify([string]$Message, [string]$Kind = 'Information') {
    if ($NoGui) { Write-Host $Message } else {
        [void][System.Windows.Forms.MessageBox]::Show($Message, 'AVI → MOV変換', 'OK', $Kind)
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
    if ($LASTEXITCODE -ne 0) { throw 'ファイルの情報を取得できません。破損や対応していない形式の可能性があります。' }
    return (($result -join "`n") | ConvertFrom-Json)
}
try {
    $script:ProbeExe = Find-Tool 'ffprobe'
    $encoder = Find-Tool 'ffmpeg'
    if (-not $InputPath) {
        if ($NoGui) { throw 'InputPathを指定してください。' }
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = '変換するAVIファイルを選択'
        $dialog.Filter = 'AVIファイル (*.avi)|*.avi'
        if ($dialog.ShowDialog() -ne 'OK') { exit 0 }
        $InputPath = $dialog.FileName
        $dialog.Dispose()
    }
    $InputPath = (Resolve-Path -LiteralPath $InputPath).Path
    if ([IO.Path]::GetExtension($InputPath) -ine '.avi') { throw 'AVIファイルを選択してください。' }
    $info = Probe @('-v','error','-select_streams','v:0','-show_entries','stream=pix_fmt,codec_name,duration:format=duration','-of','json','-i',$InputPath)
    if (@($info.streams).Count -eq 0) { throw '映像トラックがありません。' }
    $pixelFormat = $info.streams[0].pix_fmt
    $formats = Probe @('-v','error','-show_pixel_formats','-of','json')
    $descriptor = @($formats.pixel_formats | Where-Object { $_.name -eq $pixelFormat })
    $hasAlpha = $descriptor.Count -eq 1 -and $descriptor[0].flags.alpha -eq 1
    Write-Host "入力形式: $pixelFormat / アルファチャンネル: $hasAlpha"
    if (-not $hasAlpha -and -not $AllowNoAlpha) {
        $message = "アルファチャンネルを確認できませんでした（映像形式: $pixelFormat）。`n`nこのまま変換すると、透過のないMOVになります。新しい透過部分は作成されません。`n変換を続けますか？"
        if ($NoGui) { throw 'アルファがありません。承認する場合は-AllowNoAlphaを指定してください。' }
        $answer = [System.Windows.Forms.MessageBox]::Show($message, 'アルファチャンネルの警告', 'YesNo', 'Warning', 'Button2')
        if ($answer -ne 'Yes') { exit 0 }
    }
    if (-not $OutputPath) {
        $OutputPath = [IO.Path]::ChangeExtension($InputPath, '.mov')
        $number = 1
        while (Test-Path -LiteralPath $OutputPath) {
            $OutputPath = Join-Path ([IO.Path]::GetDirectoryName($InputPath)) ([IO.Path]::GetFileNameWithoutExtension($InputPath) + "_変換$number.mov")
            $number++
        }
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    if ([IO.Path]::GetExtension($OutputPath) -ine '.mov') { throw '出力先の拡張子は.movにしてください。' }
    if (Test-Path -LiteralPath $OutputPath) { throw '出力先がすでに存在します。上書きせず終了しました。' }
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($OutputPath)) ('.avi-mov-' + [guid]::NewGuid().ToString('N') + '.mov')
    $log = $OutputPath + '.log.txt'
    Write-Host "変換中です。完了するまで、このウィンドウを閉じないでください。`n保存先: $OutputPath"
    $duration = 0.0
    [void][double]::TryParse([string]$info.format.duration, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration)
    Invoke-FfmpegProgress -Encoder $encoder -Duration $duration -Activity 'AVI → MOV変換' -LogPath $log -NoGui:$NoGui -Arguments @('-n','-i',$InputPath,'-map','0:v:0','-map','0:a?','-c:v','prores_ks','-profile:v','4','-pix_fmt','yuva444p10le','-alpha_bits','16','-c:a','pcm_s24le','-movflags','+faststart',$temporary)
    $check = Probe @('-v','error','-select_streams','v:0','-show_entries','stream=codec_name,pix_fmt','-of','json','-i',$temporary)
    if ($check.streams[0].codec_name -ne 'prores' -or $check.streams[0].pix_fmt -notmatch '^yuva') { throw '出力の透過対応形式を確認できませんでした。' }
    [IO.File]::Move($temporary, $OutputPath)
    $temporary = $null
    Notify "100 %：変換が完了しました。`n`n$OutputPath`n`n形式: ProRes 4444 / 音声: PCM`n入力のアルファチャンネル: $hasAlpha"
} catch {
    Notify $_.Exception.Message 'Error'
    exit 1
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force }
}
