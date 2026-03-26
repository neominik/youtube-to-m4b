<p align="center">
  <a href="https://github.com/drewmarsh/youtube-to-m4b">
    <img src="youtube_to_m4b_banner.png" width="500" alt="Banner">
  </a>
  <br><br>Convert YouTube videos or full playlists into one chapterized .M4B audiobook with preserved metadata and configurable output quality, requires yt-dlp and ffmpeg<br><br>
</p>

## Features

- 🎧 Merges full YouTube playlists into a single audiobook file
- 🧭 Preserves and combines chapters across all videos in a playlist
- ⚙️ Configurable audio quality (64kbps-256kbps)
- 📚 Outputs M4B audiobook format
- 💻 Interactive mode or direct command execution
- 📊 Final conversion report with duration, chapter count, and bitrate

## Installing Dependencies

- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** (Latest version)
- **[FFmpeg](https://ffmpeg.org/)** (v4.4+ with AAC encoder support)

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y ffmpeg python3-pip
sudo pip3 install yt-dlp
```

```bash
# macOS (Homebrew)
brew install ffmpeg yt-dlp
```

## Script Installation

```bash
git clone https://github.com/drewmarsh/youtube-to-m4b.git
cd youtube-to-m4b

chmod +x youtube-to-m4b.sh
```

## Interactive Mode Usage

```bash
./youtube-to-m4b.sh
```

#### The script will prompt you for:
- YouTube URL
- Quality level (1-5)
- Output filename (optional)

## Direct Command Execution
```bash
./youtube-to-m4b.sh "YOUTUBE_URL" QUALITY_LEVEL "OUTPUT_NAME"
```

#### Parameters:
- YOUTUBE_URL - Full URL to the YouTube video or playlist
- QUALITY_LEVEL - Audio quality setting (1-5)
- OUTPUT_NAME (optional) - Custom filename without extension

#### Examples:
```bash
# Basic conversion with recommended quality
./youtube-to-m4b.sh "https://youtu.be/dQw4w9WgXcQ" 3

# Merge a playlist into one chapterized audiobook
./youtube-to-m4b.sh "https://www.youtube.com/playlist?list=PLAYLIST_ID" 3 "My Playlist Audiobook"

# High quality with custom filename
./youtube-to-m4b.sh "https://youtu.be/dQw4w9WgXcQ" 4 "My Audiobook Title"

# Minimal file size conversion
./youtube-to-m4b.sh "https://youtu.be/dQw4w9WgXcQ" 1 "Compact Version"
```

## Playlist Behavior

- Playlist URLs are downloaded entry-by-entry and merged into a single `.m4b`
- Each video's chapters are offset and appended so the final book keeps the full chapter list in order
- If a video has no chapter data, the script creates a fallback chapter for that entry
- The final verification step checks both total duration and chapter count before reporting success
