#!/bin/bash
# Compatible with the Bash 3.2 supplied by macOS. No Python or PowerShell required.
set -eu
export LC_NUMERIC=C
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
TOOL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP_DIR=''
ERROR_MESSAGE='処理に失敗しました。表示された内容と変換ログを確認してください。'
GUI=0

fail() { ERROR_MESSAGE=$1; printf '\nエラー: %s\n' "$1" >&2; exit 1; }

finish() {
    code=$?
    trap - EXIT
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        # Remove only the files created by this invocation.
        rm -f "$TEMP_DIR/output.mov" "$TEMP_DIR/alpha.mp4" "$TEMP_DIR/rgb.mp4"
        rmdir "$TEMP_DIR" 2>/dev/null || true
    fi
    if [ "$GUI" -eq 1 ]; then
        if [ "$code" -ne 0 ]; then
            osascript "$TOOL_DIR/notify.applescript" "$ERROR_MESSAGE" || true
        fi
        printf '\nEnterキーで終了します。'
        read -r unused || true
    fi
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT TERM

find_tool() {
    if [ -x "$COMMAND_DIR/$1" ]; then printf '%s\n' "$COMMAND_DIR/$1"; return; fi
    if [ -x "$TOOL_DIR/$1" ]; then printf '%s\n' "$TOOL_DIR/$1"; return; fi
    command -v "$1" || fail "$1が見つかりません。FFmpegとFFprobeをインストールしてください。"
}

prepare_input() {
    extension=$1
    input=$2
    if [ -z "$input" ]; then GUI=1; fi
    FFMPEG=$(find_tool ffmpeg)
    FFPROBE=$(find_tool ffprobe)
    if [ -z "$input" ]; then
        input=$(osascript "$TOOL_DIR/choose-file.applescript" "$extension")
        [ -n "$input" ] || exit 0
    fi
    [ -f "$input" ] || fail '選択したファイルが見つかりません。'
    lower_extension=$(printf '%s' "${input##*.}" | tr '[:upper:]' '[:lower:]')
    [ "$lower_extension" = "$extension" ] || fail "$extension ファイルを選択してください。"
    INPUT_DIR=$(cd "$(dirname "$input")" && pwd)
    INPUT_PATH="$INPUT_DIR/$(basename "$input")"
    STEM=$(basename "$input")
    STEM=${STEM%.*}
    PIX_FMT=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 -i "$INPUT_PATH")
    [ -n "$PIX_FMT" ] || fail '映像トラックの形式を取得できませんでした。'
    descriptors=$("$FFPROBE" -v error -show_pixel_formats -show_entries pixel_format=name:pixel_format_flags=alpha -of compact=p=0:nk=0)
    HAS_ALPHA=$(printf '%s\n' "$descriptors" | awk -F'|' -v f="$PIX_FMT" '$1 == "name=" f {for(i=2;i<=NF;i++) if($i=="flags:alpha=1") {print 1; exit}}')
    HAS_ALPHA=${HAS_ALPHA:-0}
    DURATION=$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -i "$INPUT_PATH")
    DURATION=$(printf '%s' "$DURATION" | awk '/^[0-9]+(\.[0-9]+)?$/ {print; found=1} END {if(!found) print 0}')
    printf '入力: %s\n映像形式: %s / アルファ: %s\n' "$INPUT_PATH" "$PIX_FMT" "$HAS_ALPHA"
}

run_conversion() {
    log=$1
    shift
    printf '変換を開始します。ログ: %s\n' "$log"
    started=$(date +%s)
    set +e
    "$FFMPEG" -hide_banner -nostdin -nostats -stats_period 0.5 -progress pipe:1 "$@" 2> "$log" |
    while IFS='=' read -r key value; do
        case "$key" in
            out_time_us) processed=$(awk -v t="$value" 'BEGIN {if(t~/^-?[0-9]+$/ && t>0) printf "%.3f",t/1000000; else print 0}') ;;
            speed) speed=$value ;;
            progress)
                elapsed=$(($(date +%s) - started))
                text=$(awk -v t="${processed:-0}" -v d="$DURATION" -v e="$elapsed" -v s="${speed:-計測中}" 'BEGIN {
                    if(d>0) {p=int(100*t/d); if(p>99)p=99; if(p<0)p=0;
                        if(t>0) eta=sprintf("%.0f秒（目安）",(d>t ? d-t : 0)*e/t); else eta="計算中";
                        printf "%3d %% | 処理 %.1f / %.1f 秒 | 経過 %d秒 | 残り %s | 速度 %s",p,t,d,e,eta,s;
                    } else printf "変換中 | 処理 %.1f 秒 | 経過 %d秒 | 速度 %s",t,e,s;
                }')
                printf '\r%s\033[K' "$text"
                ;;
        esac
    done
    statuses=("${PIPESTATUS[@]}")
    set -e
    printf '\n'
    [ "${statuses[0]}" -eq 0 ] && [ "${statuses[1]}" -eq 0 ] || fail "変換に失敗しました。詳細: $log"
    printf '映像の変換終了。ファイルを確認・保存しています…\n'
}

check_video() {
    codec=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 -i "$1")
    [ "$codec" = "$2" ] || fail '出力映像の確認に失敗しました。'
}

publish_file() {
    # A hard link publishes atomically and refuses any existing destination.
    # Both paths are on the same volume because the temp directory is in the output folder.
    ln "$1" "$2" || fail '出力先がすでに存在するか、書き込みに失敗しました。上書きはしていません。'
    rm -f "$1"
}

completed() {
    printf '100 %%：変換が完了しました。\n%s\n' "$1"
    if [ "$GUI" -eq 1 ]; then osascript "$TOOL_DIR/notify.applescript" "100 %：変換が完了しました。
$1"; fi
}
