#!/bin/bash
set -eu
COMMAND_DIR=$(cd "$(dirname "$0")" && pwd)
source "$COMMAND_DIR/lib/convert-common.sh"
input=''
output_dir=''
kind=mov
allow=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --input-kind) shift; [ "$#" -gt 0 ] || fail '--input-kindに形式が必要です。'; kind=$1 ;;
        --allow-no-alpha) allow=1 ;;
        --output-dir) shift; [ "$#" -gt 0 ] || fail '--output-dirに保存先が必要です。'; output_dir=$1 ;;
        *) [ -z "$input" ] || fail '入力動画は1つだけ指定してください。'; input=$1 ;;
    esac
    shift
done
case "$kind" in mov|avi) ;; *) fail '入力形式はmovまたはaviを指定してください。' ;; esac
prepare_input "$kind" "$input"
if [ "$HAS_ALPHA" -ne 1 ]; then
    if [ "$allow" -ne 1 ]; then
        if [ "$GUI" -eq 1 ]; then
            warning="アルファチャンネルを確認できませんでした（形式: ${PIX_FMT}）。
続けるとAlphaは白一色（すべて不透明）のマスク、RGBは通常の色の映像になります。
透過の新規作成は行いません。変換を続けますか？"
            answer=$(osascript "$TOOL_DIR/confirm.applescript" "$warning")
            [ "$answer" = yes ] || exit 0
        else
            fail 'アルファがありません。承認して続ける場合は --allow-no-alpha を指定してください。'
        fi
    fi
fi
OUTPUT_DIR=$(cd "${output_dir:-$INPUT_DIR}" && pwd)
alpha="$OUTPUT_DIR/${STEM}_Alpha.mp4"
rgb="$OUTPUT_DIR/${STEM}_RGB.mp4"
for file in "$alpha" "$rgb"; do
    [ ! -e "$file" ] && [ ! -L "$file" ] || fail "出力先が存在します。上書きせず終了しました: $file"
done
TEMP_DIR=$(mktemp -d "$OUTPUT_DIR/.alpha-tools.XXXXXX")
alpha_preparation=''
if [ "$HAS_ALPHA" -ne 1 ]; then alpha_preparation='format=yuva444p,'; fi
filters="[0:v:0]split=2[a][r];[a]${alpha_preparation}alphaextract,scale=in_range=full:out_range=full,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[alpha];[r]pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[rgb]"
run_conversion "$OUTPUT_DIR/${STEM}_Alpha_RGB.log.txt" -n -i "$INPUT_PATH" -filter_complex "$filters" -map '[alpha]' -an -c:v libx264 -preset medium -crf 0 -color_range pc -movflags +faststart "$TEMP_DIR/alpha.mp4" -map '[rgb]' -map '0:a?' -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -movflags +faststart "$TEMP_DIR/rgb.mp4"
check_video "$TEMP_DIR/alpha.mp4" h264
check_video "$TEMP_DIR/rgb.mp4" h264
# Publish only after both conversions and validations succeed.
ln "$TEMP_DIR/alpha.mp4" "$alpha" || fail 'Alphaの保存に失敗しました。'
if ! ln "$TEMP_DIR/rgb.mp4" "$rgb"; then
    # Roll back our just-created hard link, never an existing user file.
    if [ "$TEMP_DIR/alpha.mp4" -ef "$alpha" ]; then rm -f "$alpha"; fi
    fail 'RGBの保存に失敗しました。'
fi
completed "$alpha
$rgb
Alpha：白＝不透明、黒＝透明、灰色＝半透明"
