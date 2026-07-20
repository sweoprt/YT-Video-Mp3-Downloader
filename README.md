# YouTube Downloader App

Portable Windows downloader for:

- MP4 video
- MP3 audio
- chosen video resolution

Use this only for videos you are allowed to download.

## What changed

You do not need to install Python, `yt-dlp`, `ffmpeg`, or Deno manually for the portable launcher.

When you open `run_app.bat`, the app starts a PowerShell GUI and downloads the tools it needs into a local `bin` folder the first time you use it.

## Run it

Double-click `run_app.bat`.

Or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\portable_downloader.ps1
```

## First launch

The first time you load resolutions or download a video, the app will automatically download:

- `yt-dlp.exe`
- `ffmpeg.exe`
- `deno.exe`

They are stored locally inside this project folder, so the app stays self-contained.

## Files

- `portable_downloader.ps1` - portable Windows GUI
- `run_app.bat` - launcher
- `app.py` - older Python version kept as a backup

## Notes

- The first launch can take a little longer because the helper tools are downloaded automatically.
- The app uses the current official download URLs for `yt-dlp`, Deno, and the FFmpeg essentials build.
- `MP3` ignores the resolution selector because audio downloads do not use video resolution.
- Some videos may not offer every resolution.
