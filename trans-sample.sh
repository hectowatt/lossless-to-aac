#!/bin/bash

set -uo pipefail
START=$(date +%s)


SRC="your-files-before-trans/"
DST="your-files-after-trans/"
ERROR_LOG="$DST/errors.log"

mkdir -p "$DST"
: > "$ERROR_LOG"

TOTAL=$(find "$SRC" -type f \( -iname "*.m4a" -o -iname "*.flac" \) -print0 | xargs -0 -I {} echo {} | wc -l | tr -d ' ')
CURRENT=0

cpu_count=$(sysctl -n hw.perflevel0.physicalcpu)
echo "高性能コアの物理CPU数: $cpu_count"
echo "--------------------------------------"

{
    converted=0
    copied=0
    skipped=0
    failed=0

    while IFS= read -r -d $'\0' file; do
        [ -z "$file" ] && continue
        
        if [[ "$file" != "$SRC/"* ]]; then
            continue
        fi
        
        CURRENT=$((CURRENT+1))
        
        rel="${file#$SRC/}"
        dir=$(dirname "$rel")
        base=$(basename "$file")
        ext="${base##*.}"
        name="${base%.*}"

        printf "\r\e[K[%5d/%5d] %s " "$CURRENT" "$TOTAL" "$base"

        mkdir -p "$DST/$dir"
        ext=$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')

        case "$ext" in
            flac)
                echo -e "\n   ➜ FLAC -> AAC"
                # -nostdin を追加して、パスの食い潰し（つまみ食い）を防止
                if ffmpeg -nostdin -hide_banner -loglevel error -y \
                    -i "$file" \
                    -map 0 \
                    -map_metadata 0 \
                    -map_chapters 0 \
                    -c:v copy \
                    -c:a aac \
                    -b:a 256k \
                    "$DST/$dir/$name.m4a" 2>>"$ERROR_LOG"
                then
                    converted=$((converted+1))
                else
                    echo "失敗(FLAC変換): $rel" >> "$ERROR_LOG"
                    failed=$((failed+1))
                fi
                ;;

            m4a)
                codec=$(ffprobe -v error \
                    -select_streams a:0 \
                    -show_entries stream=codec_name \
                    -of csv=p=0 \
                    "$file" 2>/dev/null)

                if [ "$codec" = "alac" ]; then
                    echo -e "\n   ➜ ALAC -> AAC"
                    # こちらも -nostdin を追加
                    if ffmpeg -nostdin -hide_banner -loglevel error -y \
                        -i "$file" \
                        -map 0 \
                        -map_metadata 0 \
                        -map_chapters 0 \
                        -c:v copy \
                        -c:a aac \
                        -b:a 256k \
                        "$DST/$dir/$name.m4a" 2>>"$ERROR_LOG"
                    then
                        converted=$((converted+1))
                    else
                        echo "失敗(ALAC変換): $rel" >> "$ERROR_LOG"
                        failed=$((failed+1))
                    fi
                elif [ "$codec" = "aac" ]; then
                    echo -e "\n   ➜ COPY AAC"
                    if cp -p "$file" "$DST/$dir/$base" 2>>"$ERROR_LOG"; then
                        copied=$((copied+1))
                    else
                        echo "失敗(コピー): $rel" >> "$ERROR_LOG"
                        failed=$((failed+1))
                    fi
                else
                    echo -e "\n   ➜ SKIP ($codec)"
                    skipped=$((skipped+1))
                fi
                ;;
            *)
                skipped=$((skipped+1))
                ;;
        esac
    done

    END=$(date +%s)
    ELAPSED=$((END-START))

    echo
    echo
    echo "======================================"
    echo "変換完了"
    echo "======================================"
    echo
    echo "総数      : $TOTAL"
    echo "変換      : $converted"
    echo "コピー    : $copied"
    echo "スキップ  : $skipped"
    echo "失敗      : $failed"
    echo
    echo "処理時間  : ${ELAPSED} 秒"
    echo "出力先    : $DST"

    if [ "$failed" -gt 0 ]; then
        echo "エラーログ: $ERROR_LOG"
    fi
    echo "======================================"

} < <(find "$SRC" -type f \( -iname "*.m4a" -o -iname "*.flac" \) -print0)