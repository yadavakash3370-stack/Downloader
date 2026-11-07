# VideoGrab

Multi-platform **video downloader + player** for Android, built with Flutter.
Link paste karo → analyze → quality chuno → download karo, aur wahi app me offline play karo.

Sab kuch **device par** hota hai (yt-dlp + python + ffmpeg, `youtubedl-android` ke through) —
koi server, koi login, koi watermark nahi.

---

## Features

- **1000+ sites** support (yt-dlp extractors): YouTube, Instagram, Facebook, TikTok, X (Twitter),
  Vimeo, Dailymotion, Reddit, Twitch clips, news sites, etc.
- **Quality chooser** — 144p se 4K tak jo site offer kare, plus "Best" aur **audio-only (m4a)**.
- **In-app player** — downloaded file ya direct stream, seek, speed (0.5x–2x), fullscreen.
- **Offline library** — history, thumbnail, size, date; play / save copy / delete.
- **Downloads folder copy** — `Download/VideoGrab/` me bhi save (toggle settings me).
- **Engine updater** — yt-dlp ek tap se latest release par update (extractor tootne par kaam aata hai).
- **SVG icons only** — sab icons hand-written SVG assets hain, emoji ya material glyph nahi.
- Dark + neon UI (violet → cyan gradient), Material 3.

## Screens

| Tab | Kya karta hai |
| --- | --- |
| Download | Link paste/analyze, quality chips, download progress, quick play |
| Library | Downloaded videos list, play, save copy, delete |
| Settings | Engine version + update, save-copy toggle, how-to, about |

## APK download

Har successful build par APK **GitHub Release** me chala jata hai (direct download button):

**https://github.com/yadavakash3370-stack/Downloader/releases/latest**

| APK | Size | Kab chunein |
| --- | --- | --- |
| `VideoGrab-full-arm64-v8a.apk` | ~65 MB | **Recommended** — ffmpeg bundled: best video + best audio merge, audio → m4a, har quality |
| `VideoGrab-lite-arm64-v8a.apk` | ~30 MB | Chhoti size chahiye — single-file formats (720p tak), no merge |
| `VideoGrab-lite-armeabi-v7a.apk` | ~29 MB | Purane 32-bit phones |

Phone par: APK tap → "Unknown sources" allow → install.
(Zyada purana process: Actions → run → Artifacts, wahan bhi milte hain.)

### Full vs Lite

| Feature | Full | Lite |
| --- | --- | --- |
| 1080p/4K (separate video+audio merge) | Yes | — |
| 720p tak single-file | Yes | Yes |
| Audio-only extract to m4a | Yes | native audio file (m4a/webm) |
| APK size | ~65 MB | ~30 MB |

App build ke waqt hi detect kar leta hai ki ffmpeg hai ya nahi, isliye dono
variants same codebase se bante hain. Settings me "Full build / Lite build" dikh jata hai.

### Build pipeline

`.github/workflows/build-apk.yml` har push (aur manual dispatch) par:

1. **Lite** arm64 + armv7 build (`videograb.withFfmpeg=false` → ffmpeg natives skip)
2. **Full** arm64 build (ffmpeg included)
3. Artifacts upload + **Release `latest` update** with the three APKs

Stack: Flutter 3.29.3 · Dart 3 · AGP 8.7.3 · Kotlin 2.1.0 · Gradle 8.12 · Java 17 ·
minSdk 24 (Android 7.0+) · targetSdk 35.

## Local build

```bash
flutter pub get
flutter build apk --release --split-per-abi
# output: build/app/outputs/flutter-apk/
```

Android SDK 35 + JDK 17 chahiye. First run par app python runtime extract karta hai
(isliye pehla launch 10–20s le sakta hai).

## Project layout

```
lib/
  main.dart                 app entry + theme
  screens/                  home, library, settings, player
  widgets/svg_icon.dart     SVG icon + gradient button kit
  services/engine.dart      MethodChannel bridge to native yt-dlp
  services/library_store.dart, settings_store.dart
  models/                   MediaInfo, DownloadItem
android/app/src/main/kotlin/com/videograb/app/
  MainActivity.kt           channel registration
  DownloadBridge.kt         probe / download / cancel / stream / save / delete
assets/icons/               30 hand-written SVG icons (no emoji)
```

### Native bridge API

| Method | Description |
| --- | --- |
| `init` | python + yt-dlp + ffmpeg runtime setup |
| `probe` | `--dump-json` info → title, thumbnail, duration, heights, sizes |
| `download` | runs yt-dlp with progress events (`progress` / `stage` / `done` / `failed`) |
| `cancel` | kills the running yt-dlp process |
| `streamUrl` | resolves a direct playable URL for in-app playback |
| `updateEngine` | updates the bundled yt-dlp binary |
| `saveCopy` / `deleteFile` | MediaStore export and cleanup |

## Libraries used

- [`youtubedl-android`](https://github.com/yausername/youtubedl-android) `0.18.1` (library + ffmpeg)
- `flutter_svg`, `video_player`, `shared_preferences`, `path_provider`, `permission_handler`

## Legal

Sirf wahi content download karo jiska aap owner ho ya jiske liye platform ki terms allow karti hain.
App koi DRM-protected ya paid content bypass nahi karta.
