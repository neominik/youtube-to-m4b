#!/bin/bash

set -euo pipefail

validate_quality() {
  [[ "$1" =~ ^[1-5]$ ]] || {
    echo "Invalid quality. Please enter a number between 1-5."
    return 1
  }
}

validate_url() {
  [[ -z "$1" ]] && {
    echo "URL cannot be empty."
    return 1
  }

  return 0
}

validate_filename() {
  [[ -z "$1" ]] && {
    echo "Filename cannot be empty."
    return 1
  }

  return 0
}

get_input() {
  local prompt="$1"
  local validator="$2"
  local default="$3"
  local input=""

  while true; do
    read -r -p "$prompt" input
    [[ -z "$input" && -n "$default" ]] && input="$default"
    "$validator" "$input" && break
  done

  echo "$input"
}

get_bitrate() {
  case "$1" in
    1) echo "64k" ;;
    2) echo "96k" ;;
    3) echo "128k" ;;
    4) echo "192k" ;;
    5) echo "256k" ;;
    *) return 1 ;;
  esac
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: Required command not found: $1"
    exit 1
  }
}

cleanup() {
  if [[ -n "${temp_dir:-}" && -d "$temp_dir" ]]; then
    rm -rf "$temp_dir"
  fi
}

if [[ $# -ge 2 ]]; then
  url="$1"
  quality="$2"
  output_name="${3:-audiobook}"

  validate_url "$url" || exit 1
  validate_quality "$quality" || exit 1
  validate_filename "$output_name" || exit 1
elif [[ $# -eq 0 ]]; then
  echo "======================================================"
  echo "       YouTube URL to .m4b Audiobook Converter"
  echo "======================================================"
  echo "Quality Levels:"
  echo "1. 64 kbps   (Smallest file size)"
  echo "2. 96 kbps   (Good balance)"
  echo "3. 128 kbps  (Recommended)"
  echo "4. 192 kbps  (High quality)"
  echo "5. 256 kbps  (Best quality)"
  echo ""

  url=$(get_input "Enter YouTube URL: " validate_url "")
  quality=$(get_input "Select audio quality (1-5): " validate_quality "")
  output_name=$(get_input "Enter output name [default: audiobook]: " validate_filename "audiobook")
else
  echo "Usage: $0 \"[URL]\" [QUALITY] \"[OUTPUT_NAME]\""
  echo "Examples:"
  echo "  Interactive mode: $0"
  echo "  Direct mode: $0 \"https://youtube.com/watch?v=...\" 3 \"Neverwhere (1996)\""
  exit 1
fi

require_command yt-dlp
require_command ffmpeg
require_command ffprobe
require_command python3

bitrate=$(get_bitrate "$quality")
output_file="${output_name}.m4b"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/youtube-to-m4b.XXXXXX")
metadata_json="$temp_dir/metadata.json"
downloads_list="$temp_dir/downloads.txt"
ffmetadata_file="$temp_dir/ffmetadata.txt"
trap cleanup EXIT

echo "Starting conversion:"
echo "  URL: $url"
echo "  Quality: Level $quality ($bitrate)"
echo "  Output: $output_file"
echo ""

echo "Fetching metadata from YouTube..."
yt-dlp --dump-single-json --no-warnings --yes-playlist "$url" > "$metadata_json"

echo "Downloading audio from YouTube..."
yt-dlp --quiet --no-warnings \
       --yes-playlist \
       -f "bestaudio/best" \
       -o "$temp_dir/%(autonumber)03d-%(id)s.%(ext)s" \
       --print after_move:filepath \
       "$url" > "$downloads_list"

audio_files=()
while IFS= read -r file_path || [[ -n "$file_path" ]]; do
  [[ -n "$file_path" ]] || continue
  audio_files+=("$file_path")
done < "$downloads_list"

if [[ ${#audio_files[@]} -eq 0 ]]; then
  echo "Error: Audio download failed"
  exit 1
fi

echo "Building combined chapter metadata..."
metadata_stats=$(python3 - "$metadata_json" "$ffmetadata_file" "$output_name" "$url" <<'PY'
import json
import sys

metadata_path, ffmetadata_path, output_title, source_url = sys.argv[1:5]


def esc(value):
    text = "" if value is None else str(value)
    text = text.replace("\\", "\\\\")
    text = text.replace("\n", "\\\n")
    text = text.replace(";", "\\;")
    text = text.replace("#", "\\#")
    text = text.replace("=", "\\=")
    return text


with open(metadata_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

entries = data.get("entries") or [data]
playlist_mode = len(entries) > 1
playlist_title = data.get("title") or output_title
playlist_description = data.get("description") or ""

artists = []
for entry in entries:
    artist = entry.get("artist") or entry.get("uploader") or entry.get("channel")
    if artist:
        artists.append(artist)

artist_name = artists[0] if artists and len(set(artists)) == 1 else "Various"

chapters = []
current_offset_ms = 0

for entry in entries:
    entry_title = entry.get("title") or entry.get("id") or "Untitled"
    entry_duration = entry.get("duration")
    if entry_duration is None:
        raise SystemExit(f"Missing duration for entry: {entry_title}")

    entry_duration_ms = int(round(float(entry_duration) * 1000))
    entry_chapters = entry.get("chapters") or []

    if entry_chapters:
        for index, chapter in enumerate(entry_chapters):
            start_time = chapter.get("start_time")
            if start_time is None:
                continue

            end_time = chapter.get("end_time")
            if end_time is None:
                if index + 1 < len(entry_chapters):
                    end_time = entry_chapters[index + 1].get("start_time")
                else:
                    end_time = float(entry_duration)

            start_ms = current_offset_ms + int(round(float(start_time) * 1000))
            end_ms = current_offset_ms + int(round(float(end_time) * 1000))
            end_ms = min(end_ms, current_offset_ms + entry_duration_ms)

            if end_ms <= start_ms:
                continue

            chapter_title = chapter.get("title") or entry_title
            if playlist_mode:
                chapter_title = f"{entry_title} - {chapter_title}"

            chapters.append((start_ms, end_ms, chapter_title))
    else:
        chapters.append((current_offset_ms, current_offset_ms + entry_duration_ms, entry_title))

    current_offset_ms += entry_duration_ms

description_lines = [f"Combined from {len(entries)} YouTube videos."]
if playlist_title and playlist_title != output_title:
    description_lines.append(f"Playlist: {playlist_title}")
description_lines.append(f"Source: {source_url}")
if playlist_description:
    description_lines.append(playlist_description)

with open(ffmetadata_path, "w", encoding="utf-8") as handle:
    handle.write(";FFMETADATA1\n")
    handle.write(f"title={esc(output_title)}\n")
    handle.write(f"album={esc(playlist_title)}\n")
    handle.write(f"artist={esc(artist_name)}\n")
    handle.write("genre=Audiobook\n")
    handle.write(f"comment={esc(source_url)}\n")
    handle.write(f"description={esc(chr(10).join(description_lines))}\n")

    for start_ms, end_ms, chapter_title in chapters:
        handle.write("[CHAPTER]\n")
        handle.write("TIMEBASE=1/1000\n")
        handle.write(f"START={start_ms}\n")
        handle.write(f"END={end_ms}\n")
        handle.write(f"title={esc(chapter_title)}\n")

print(f"{current_offset_ms}\t{len(chapters)}\t{len(entries)}")
PY
)

expected_duration_ms=$(printf '%s\n' "$metadata_stats" | python3 -c 'import sys; print(sys.stdin.read().strip().split("\t")[0])')
chapter_count=$(printf '%s\n' "$metadata_stats" | python3 -c 'import sys; print(sys.stdin.read().strip().split("\t")[1])')
entry_count=$(printf '%s\n' "$metadata_stats" | python3 -c 'import sys; print(sys.stdin.read().strip().split("\t")[2])')

echo "Converting ${entry_count} input files into one M4B..."
ffmpeg_inputs=()
concat_streams=""
input_index=0

for audio_file in "${audio_files[@]}"; do
  ffmpeg_inputs+=("-i" "$audio_file")
  concat_streams="${concat_streams}[${input_index}:a:0]"
  input_index=$((input_index + 1))
done

metadata_input_index=$input_index

ffmpeg -y \
       "${ffmpeg_inputs[@]}" \
       -i "$ffmetadata_file" \
       -filter_complex "${concat_streams}concat=n=${#audio_files[@]}:v=0:a=1[aout]" \
       -map "[aout]" \
       -map_metadata "$metadata_input_index" \
       -map_chapters "$metadata_input_index" \
       -c:a aac -b:a "$bitrate" \
       -movflags +faststart \
       -vn -dn \
       "$output_file"

echo "Verifying output..."
verification_json=$(ffprobe -v error -print_format json -show_entries format=duration -show_chapters "$output_file")
verification_stats=$(printf '%s\n' "$verification_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); duration=float(data.get("format", {}).get("duration", 0.0)); chapters=len(data.get("chapters", [])); print(f"{duration}\t{chapters}")')
actual_duration_seconds=$(printf '%s\n' "$verification_stats" | python3 -c 'import sys; print(sys.stdin.read().strip().split("\t")[0])')
actual_chapter_count=$(printf '%s\n' "$verification_stats" | python3 -c 'import sys; print(sys.stdin.read().strip().split("\t")[1])')
actual_duration_ms=$(python3 -c 'import sys; print(int(round(float(sys.argv[1]) * 1000)))' "$actual_duration_seconds")

if [[ "$actual_chapter_count" != "$chapter_count" ]]; then
  echo "Error: Expected $chapter_count chapters but found $actual_chapter_count in $output_file"
  exit 1
fi

duration_delta_ms=$((actual_duration_ms - expected_duration_ms))
if [[ $duration_delta_ms -lt 0 ]]; then
  duration_delta_ms=$((duration_delta_ms * -1))
fi

if [[ $duration_delta_ms -gt 5000 ]]; then
  echo "Error: Expected duration close to ${expected_duration_ms}ms but found ${actual_duration_ms}ms"
  exit 1
fi

duration_formatted=$(python3 -c 'import sys; total=int(round(float(sys.argv[1]))); print(f"{total // 3600}h {(total % 3600) // 60:02d}m {total % 60:02d}s")' "$actual_duration_seconds")
actual_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$output_file" | python3 -c 'import sys; values=[line.strip() for line in sys.stdin if line.strip()]; print(f"{round(int(values[0]) / 1000)} kbps" if values else "unknown")')

echo ""
echo "======================================================"
echo "Conversion complete!"
echo "Output file: $output_file"
echo "Duration: $duration_formatted"
echo "Chapters: $actual_chapter_count"
echo "Bitrate: $actual_bitrate"
echo "======================================================"
