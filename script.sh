#!/bin/bash
# Safety for GitHub runners (standard bash)
set -e

# --- CONFIGURATION (GitHub Compatible) ---
# We use the current directory ($PWD) instead of /tmp for better GitHub Artifact support
BASE_DIR="$PWD"
TMP="$BASE_DIR/tmp_processing"
INPUT_DIR="$BASE_DIR/reels"
AUDIO_DIR="$BASE_DIR/audio"
LOGO_PATH="$BASE_DIR/spotify.png"
QUOTES_FILE="$BASE_DIR/quotes.txt"
OUTPUT_DIR="$BASE_DIR/out"

# Font Logic: Tries to find Inter-Black in the repo, otherwise falls back to Linux default
FONT_PATH="$BASE_DIR/Inter-Black.ttf"
if [ ! -f "$FONT_PATH" ]; then
    FONT_PATH="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
fi

mkdir -p "$TMP" "$OUTPUT_DIR"

# 1. ASSET CHECK
if [ ! -f "$LOGO_PATH" ]; then echo "❌ spotify.png missing"; exit 1; fi
if [ ! -f "$QUOTES_FILE" ]; then echo "❌ quotes.txt missing"; exit 1; fi

FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)

if [ ${#FILES[@]} -eq 0 ]; then echo "❌ No videos in $INPUT_DIR"; exit 1; fi

# 2. PROCESS & MERGE CLIPS
echo "🎬 Step 1: Processing Clips..."
i=1
for f in "${FILES[@]}"; do
  ffmpeg -i "$f" -t 1 -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black,fps=30" \
    -c:v libx264 -preset superfast -pix_fmt yuv420p -an "$TMP/clip_$i.mp4" -y -loglevel error
  echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

MERGED_RAW="$TMP/merged_raw.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$MERGED_RAW" -y -loglevel error
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_RAW")

# 3. APPLY LOGO AND QUOTE
echo "🎨 Step 2: Applying Visuals..."
TOTAL=$(wc -l < "$QUOTES_FILE" | xargs)
line=$((RANDOM % TOTAL + 1))

# CLEANING: This Perl command removes the "ghost boxes" effectively
raw=$(sed -n "${line}p" "$QUOTES_FILE" | perl -pe 's/[^[:ascii:]]//g; s/[\x00-\x1f\x7f]//g' | xargs)
echo "$raw" | fold -s -w 35 > "$TMP/quote.txt"

logo_start=$(echo "$DUR" | awk '{print $1 / 2}')
logo_fade=$(echo "$DUR" | awk '{print $1 - 1.2}')

# SIZES UPDATED: scale=180 (Logo) and fontsize=38 (Text)
# POSITION: y=H-h-100 (Logo near bottom)
FILTER="[1:v]loop=-1:1:0,scale=180:-1,format=rgba,fade=t=in:st=${logo_start}:d=0.5:alpha=1,fade=t=out:st=${logo_fade}:d=0.5:alpha=1[logo_p]; \
[0:v][logo_p]overlay=x=(W-w)/2:y=H-h-100:shortest=1[v_l]; \
[v_l]drawtext=fontfile='${FONT_PATH}':textfile='$TMP/quote.txt':fontcolor=white:fontsize=38: \
box=1:boxcolor=black@0.7:boxborderw=20:line_spacing=15:x=(w-text_w)/2:y=(h*0.15):expansion=none[v_f]"

VISUAL_MASTER="$TMP/visual_master.mp4"
ffmpeg -i "$MERGED_RAW" -i "$LOGO_PATH" -filter_complex "$FILTER" \
  -map "[v_f]" -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p -an "$VISUAL_MASTER" -y -loglevel warning

# 4. FINAL AUDIO GLUE
echo "🎵 Step 3: Adding Audio..."
FADE_VAL=$(echo "$DUR" | awk '{print ($1 > 2) ? $1 - 2 : 0}')
safe=$(echo "$raw" | tr -cd '[:alnum:] ' | cut -c1-50 | xargs)
out="$OUTPUT_DIR/${safe}.mp4"

ffmpeg -i "$VISUAL_MASTER" -i "$AUDIO_FILE" \
  -filter_complex "[1:a]afade=t=out:st=${FADE_VAL}:d=2[aud]" \
  -map 0:v -map "[aud]" -c:v copy -c:a aac -shortest "$out" -y -loglevel warning

echo "✅ SUCCESS! Video saved to: $out"
rm -rf "$TMP"
