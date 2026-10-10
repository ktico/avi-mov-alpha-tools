# AVI / MOV Alpha変換ツール

WindowsとmacOSで使う、FFmpegによる動画変換ツールです。

- **AVI → MOV**：アルファの有無を確認し、ProRes 4444のMOVに変換します。アルファがない場合は警告し、承認された場合だけ続行します。
- **MOV → Alpha / RGB**：アルファ付きMOVから、`元の名前_Alpha.mp4`と`元の名前_RGB.mp4`を作ります。
- **AVI → Alpha / RGB**：AVIから直接、`元の名前_Alpha.mp4`と`元の名前_RGB.mp4`を作ります。中間MOVは作りません。アルファがない場合は警告し、承認された場合は白一色のAlphaマスクを出力します。
- 進捗率・処理済みの尺・経過時間・推定残り時間を表示します。
- 元の動画は変更しません。既存の出力は上書きしません。

## 必要なもの

FFmpegとFFprobeをインストールし、コマンドとして使える状態にしてください。
FFmpegのビルドには`prores_ks`と`libx264`が必要です。
Windowsは標準のWindows PowerShell、Macは標準のBashとAppleScriptを使用します。
MacにPythonやPowerShellを追加する必要はありません。

## Windowsでの使い方

1. ReleaseのWindows用ZIPを展開します。
2. AVIを変換する場合は`AVI_MOV変換/AVI_MOV変換.cmd`をダブルクリックします。
3. MOVを分離する場合は`MOV_Alpha_RGB変換/MOV_Alpha_RGB変換.cmd`をダブルクリックします。
4. AVIを直接分離する場合は`AVI_Alpha_RGB変換.cmd`をダブルクリックします。
5. ファイルを選び、完了メッセージが出るまで待ちます。

FFmpegがPATHにない場合は、それぞれのツールのフォルダに`ffmpeg.exe`と`ffprobe.exe`を置いても使えます。
各フォルダの`.cmd`と2つの`.ps1`は一緒に移動してください。
`AVI_Alpha_RGB変換.cmd`は隣にある`MOV_Alpha_RGB変換`フォルダの処理を使うので、このフォルダと一緒に保管してください。

## Macでの使い方

1. ReleaseのMac用ZIPを展開します。
2. AVIを変換する場合は`avi-to-mov.command`をダブルクリックします。
3. MOVを分離する場合は`mov-to-alpha-rgb.command`をダブルクリックします。
4. AVIを直接分離する場合は`avi-to-alpha-rgb.command`をダブルクリックします。
5. ファイル選択画面で動画を選びます。ターミナルに進捗が表示されます。
6. 完了メッセージを閉じ、ターミナルでEnterを押して終了します。

3つの`.command`と`lib`フォルダを一緒に保管してください。
Intel Mac・AppleシリコンのHomebrewの一般的な場所も検索します。
Finderから起動できない場合は、ターミナルで`bash `に続けて`.command`をドラッグし、Enterを押して実行できます。

コマンドから使う場合の例：

```bash
bash mac/avi-to-mov.command "/path/to/video.avi"
bash mac/avi-to-mov.command --allow-no-alpha "/path/to/video.avi"
bash mac/mov-to-alpha-rgb.command "/path/to/video.mov"
bash mac/avi-to-alpha-rgb.command "/path/to/video.avi"
bash mac/avi-to-alpha-rgb.command --allow-no-alpha "/path/to/video.avi"
```

ファイルパスを指定した場合はGUIを出しません。AVIにアルファがない場合は、明示的な`--allow-no-alpha`がなければ停止します。

## 保存されるもの

入力と同じフォルダに保存します。

| 入力 | 出力 |
| --- | --- |
| `sample.avi` | `sample.mov` |
| `sample.mov` | `sample_Alpha.mp4`、`sample_RGB.mp4` |
| `sample.avi`（直接分離） | `sample_Alpha.mp4`、`sample_RGB.mp4` |

AVI変換の同名MOVがある場合は`_変換1`などを追加します。
MOV・AVI分離では、AlphaまたはRGBの同名ファイルがある場合は停止します。
変換ログも出力と同じ場所に保存します。

## 形式とアルファの扱い

MOVはProRes 4444、アルファ16bit、音声PCM 24bitです。
アルファの判定はFFprobeが報告するピクセル形式のalphaフラグに基づきます。
アルファがあるが全画素が不透明な動画も「アルファあり」と判定します。
アルファなしのAVIを承認して変換しても、背景の切り抜きや透過の新規作成は行いません。

Alpha MP4は、白＝不透明、黒＝透明、灰色＝半透明の白黒マスクです。
H.264可逆圧縮、8bit・フルレンジ（0～255）、音声なしです。
元の10/16bitアルファは8bitに変換されます。可逆圧縮のH.264は一部の再生ソフトで対応しない場合があります。

RGB MP4は色の映像をH.264（CRF 18）、音声をAAC（192kbps）で保存します。
名前はRGBですが、保存形式は一般的なYUV 4:2:0です。
AlphaもRGBもMP4そのものに透過を埋め込む形式ではありません。編集ソフトでAlphaをRGBのマスクとして適用してください。
RGBは元の色を取り出します。黒背景への合成や、元素材のプリマルチプライの補正は行いません。

最初の映像トラックと、すべての音声トラックを使用します（Alphaは無音）。
MP4分離で幅・高さが奇数の場合は、右・下に最大1ピクセル追加して両方を偶数サイズにそろえます。
尺が取得できない場合は、割合の代わりに処理済み時間を表示します。
推定残り時間は目安です。変換が終わるまでウィンドウを閉じないでください。

## 検証

GitHub ActionsでWindowsとmacOSのネイティブ環境を使い、実際にFFmpegを実行して検証します。
アルファ付き・なしのAVI、警告承認の有無、Alphaの白黒値、フレーム数と尺、RGBの音声、同名出力の拒否、奇数サイズ、日本語・空白を含むパスを確認します。
MacのAppleScriptはネイティブコンパイラで構文を検証します。
自動テストでFinderのダブルクリックやファイル選択画面を手動操作する検証は行いません。

FFmpegの仕様：[ProRes](https://ffmpeg.org/ffmpeg-codecs.html)、[alphaextract](https://ffmpeg.org/ffmpeg-filters.html#alphaextract)、[progress](https://ffmpeg.org/ffmpeg.html)。

FFmpegは同梱しません。
