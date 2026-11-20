# get video from

script for download video from ...

```java
=== Video Downloader Help ===
Usage:
  1. Download a single video:
     .\get_video.ps1 -n "Video Name" -u "https://.../playlist.m3u8" [-dir_dst "result"]

  2. Batch download from a JSON file:
     .\get_video.ps1 -f "videos.json" [-dir_dst "result"]

Parameters:
  -n, -Name      Output video filename (without .mp4)
  -u, -Url       Direct link to .m3u8 playlist
  -f, -File      Path to JSON file
  -d, -dir_dst   Destination folder for downloaded videos (default: .\result)
  -h, -Help      Show this help message

Directory Structure:
  .\bin\         Must contain yt-dlp.exe, ffmpeg.exe, ffprobe.exe (and .dll files)
  .\result\      Default output folder (created automatically)

JSON File Format Example (UTF-8):
  [
    {
      "name": "Lecture 1 - Introduction",
      "url": "https://.../playlist.m3u8"
    },
    {
      "name": "Lecture 2 - Logic",
      "url": "https://.../playlist.m3u8"
    }
  ]
```
