#!/bin/bash
set -eu
COMMAND_DIR=$(cd "$(dirname "$0")" && pwd)
source "$COMMAND_DIR/lib/convert-common.sh"
input=''
output_dir=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir) shift; [ "$#" -gt 0 ] || fail '--output-dirに保存先が必要です。'; output_dir=$1 ;;
        *) [ -z "$input" ] || fail '入力MOVは1つだけ指定してください。'; input=$1 ;;
    esac
    shift
done
prepare_input mov "$input"
[ "$HAS_ALPHA" -eq 1 ] || fail "アルファチャンネルを確認できませんでした（形式: $PIX_FMT）。アルファ付きMOVを選択してください。"
OUTPUT_DIR=$(cd "${output_dir:-$INPUT_DIR}" && pwd)
alpha="$OUTPUT_DIR/${STEM}_Alpha.mp4"
rgb="$OUTPUT_DIR/${STEM}_RGB.mp4"
for file in "$alpha" "$rgb"; do
    [ ! -e "$file" ] && [ ! -L "$file" ] || fail "出力先が存在します。上書きせず終了しました: $file"
done
TEMP_DIR=$(mktemp -d "$OUTPUT_DIR/.alpha-tools.XXXXXX")
filters='[0:v:0]split=2[a][r];[a]alphaextract,scale=in_range=full:out_range=full,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[alpha];[r]pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p[rgb]'
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
