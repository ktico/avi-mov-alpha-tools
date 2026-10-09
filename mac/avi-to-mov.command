#!/bin/bash
set -eu
COMMAND_DIR=$(cd "$(dirname "$0")" && pwd)
source "$COMMAND_DIR/lib/convert-common.sh"

allow=0
input=''
output=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --allow-no-alpha) allow=1 ;;
        --output) shift; [ "$#" -gt 0 ] || fail '--outputに保存先が必要です。'; output=$1 ;;
        *) [ -z "$input" ] || fail '入力AVIは1つだけ指定してください。'; input=$1 ;;
    esac
    shift
done
prepare_input avi "$input"
if [ "$HAS_ALPHA" -ne 1 ] && [ "$allow" -ne 1 ]; then
    warning="アルファチャンネルを確認できませんでした（形式: ${PIX_FMT}）。
変換を続けると透過のないMOVになります。新しい透過部分は作成しません。
変換を続けますか？"
    if [ "$GUI" -eq 1 ]; then
        answer=$(osascript "$TOOL_DIR/confirm.applescript" "$warning")
        [ "$answer" = yes ] || exit 0
    else
        fail 'アルファがありません。承認して続ける場合は --allow-no-alpha を指定してください。'
    fi
fi
if [ -z "$output" ]; then
    output="$INPUT_DIR/$STEM.mov"
    n=1
    while [ -e "$output" ] || [ -L "$output" ]; do
        output="$INPUT_DIR/${STEM}_変換$n.mov"
        n=$((n+1))
    done
fi
case "$output" in *.[mM][oO][vV]) ;; *) fail '出力の拡張子は.movにしてください。' ;; esac
OUTPUT_DIR=$(cd "$(dirname "$output")" && pwd)
output="$OUTPUT_DIR/$(basename "$output")"
[ ! -e "$output" ] && [ ! -L "$output" ] || fail '出力先が存在します。上書きせず終了しました。'
TEMP_DIR=$(mktemp -d "$OUTPUT_DIR/.alpha-tools.XXXXXX")
run_conversion "$output.log.txt" -n -i "$INPUT_PATH" -map 0:v:0 -map '0:a?' -c:v prores_ks -profile:v 4 -pix_fmt yuva444p10le -alpha_bits 16 -c:a pcm_s24le -movflags +faststart "$TEMP_DIR/output.mov"
check_video "$TEMP_DIR/output.mov" prores
output_format=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 -i "$TEMP_DIR/output.mov")
case "$output_format" in yuva*) ;; *) fail '出力のアルファ対応形式を確認できませんでした。' ;; esac
publish_file "$TEMP_DIR/output.mov" "$output"
completed "$output"
