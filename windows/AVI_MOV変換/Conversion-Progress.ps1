function Invoke-FfmpegProgress {
    param([string]$Encoder, [string[]]$Arguments, [double]$Duration,
          [string]$Activity, [string]$LogPath, [switch]$NoGui)
    $form = $null
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $processed = 0.0
    $speed = '計測中'
    $lastPrinted = -10
    $previousPreference = $ErrorActionPreference
    try {
        if (-not $NoGui) {
            $form = New-Object System.Windows.Forms.Form
            $form.Text = $Activity
            $form.ClientSize = New-Object System.Drawing.Size(560, 145)
            $form.StartPosition = 'CenterScreen'
            $form.FormBorderStyle = 'FixedDialog'
            $form.ControlBox = $false
            $label = New-Object System.Windows.Forms.Label
            $label.SetBounds(18, 15, 520, 55)
            $label.Text = '変換を開始しています…'
            $bar = New-Object System.Windows.Forms.ProgressBar
            $bar.SetBounds(18, 76, 520, 24)
            if ($Duration -le 0) { $bar.Style = 'Marquee' }
            $note = New-Object System.Windows.Forms.Label
            $note.SetBounds(18, 111, 520, 25)
            $note.Text = '完了するまで起動したウィンドウを閉じないでください。'
            $form.Controls.AddRange(@($label, $bar, $note))
            $form.Show()
            [System.Windows.Forms.Application]::DoEvents()
        }
        $ErrorActionPreference = 'Continue'
        & $Encoder -hide_banner -nostdin -nostats -stats_period 0.5 -progress pipe:1 @Arguments 2> $LogPath | ForEach-Object {
            $line = [string]$_
            if ($line -match '^out_time_us=(-?\d+)$') {
                $processed = [Math]::Max(0, [double]$Matches[1] / 1000000)
            } elseif ($line -match '^speed=(.+)$') {
                $speed = $Matches[1]
            } elseif ($line -match '^progress=') {
                $percent = 0
                if ($Duration -gt 0) { $percent = [int][Math]::Min(99, [Math]::Floor($processed / $Duration * 100)) }
                $elapsed = [int]$timer.Elapsed.TotalSeconds
                $remaining = '計算中'
                if ($processed -gt 0 -and $Duration -gt 0) {
                    $remaining = ([int][Math]::Ceiling([Math]::Max(0, $Duration - $processed) * $timer.Elapsed.TotalSeconds / $processed)).ToString() + '秒（目安）'
                }
                $status = "処理済み $([Math]::Round($processed, 1)) / $([Math]::Round($Duration, 1)) 秒　経過 ${elapsed}秒　残り $remaining"
                if ($Duration -le 0) { $status = "処理済み $([Math]::Round($processed, 1)) 秒　経過 ${elapsed}秒（総尺を取得できません）" }
                if ($line -eq 'progress=end') { $status = '映像の変換終了。ファイルを確認・保存しています…' }
                if ($form) {
                    $headline = "$percent %　速度: $speed"
                    if ($Duration -le 0) { $headline = "変換中　速度: $speed" }
                    $label.Text = "$headline`n$status"
                    if ($Duration -gt 0) { $bar.Value = $percent }
                    [System.Windows.Forms.Application]::DoEvents()
                } else {
                    Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
                    if ($percent -ge $lastPrinted + 10 -or $line -eq 'progress=end') {
                        Write-Host "$Activity : $percent % / $status"
                        $lastPrinted = $percent
                    }
                }
            }
        }
        $conversionExit = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($conversionExit -ne 0) { throw "変換に失敗しました（終了コード: $conversionExit）。詳細: $LogPath" }
    } finally {
        $ErrorActionPreference = $previousPreference
        $timer.Stop()
        Write-Progress -Activity $Activity -Completed
        if ($form) { $form.Close(); $form.Dispose() }
    }
}
