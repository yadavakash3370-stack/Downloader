# VideoGrab

Android par **multi-platform video downloader + in-app player + PW study browser**.
Link paste karo → platform turant pata chalta hai → quality chuno → download ya play karo.

Sab kuch **device par** hota hai (`youtubedl-android` = on-device python + yt-dlp + optional ffmpeg) —
koi server, koi watermark nahi.

---

## Features

- **Instant platform detection** — link type karte hi host se YouTube / Instagram / Facebook /
  TikTok / X / Vimeo / Dailymotion / Physics Wallah / direct media pehchan liya jata hai
  (koi network request nahi, analyse se pehle).
- **1000+ sites** (yt-dlp extractors) + direct MP4 / HLS / DASH links.
- **Better quality** — full build me best video + best audio merge, codec-compatible container
  automatically (`--merge-output-format mp4` force nahi hota). `Best` (reliable h264/AAC MP4),
  `Max` (site ka sabse bada format, AV1/VP9 bhi) aur 144p–4K chips. Lite build me progressive formats.
- **Faster downloads** — parallel fragments (`-N`), chunked HTTP range requests, 64K buffer,
  shorter timeouts. Settings me 1× / 4× / 8× / 16× Turbo choose karo (default 8×).
- **PW account login** — app ke andar mobile number + OTP se apne Physics Wallah account me login
  (ya PW website par login, app use pehchan leta hai). Login sirf phone me save hota hai.
- **PW lecture links** — `pw.live/watch/?…` link Download tab me daalein: app use aapke account se
  kholta hai. YouTube / plain stream wale lectures download hote hain; DRM-protected lectures ke
  liye "PW player me dekhein" button milta hai.
- **PW tab** — `pw.live` official site app ke andar: lectures site ke apne player me chalte hain
  (DRM lectures bhi, phone ke built-in Widevine se), landscape fullscreen ke saath.
- **In-app player** — downloaded file ya direct stream, seek, speed (0.5x–2x), fullscreen.
- **Offline library** — history, thumbnail, size, date; play / save copy / delete.
- **Downloads folder copy** — `Download/VideoGrab/` me bhi save (Settings me toggle).
- **Engine updater** — yt-dlp ek tap se latest release par update.
- **SVG icons only** — sab icons hand-written SVG assets hain, emoji nahi.
- Clean, neutral dark Material 3 UI.

## Screens

| Tab | Kya karta hai |
| --- | --- |
| Download | Instant platform badge, link analyze, quality chips, download progress, quick play |
| Library | Downloaded videos, play, save copy, delete |
| PW | Official `pw.live` site, account status, lectures fullscreen, detected media → Play / Download |
| Settings | PW account login/logout, speed control, engine version + update, storage, guide |

## APK download

Har successful build par APK **GitHub Release** me chala jata hai (direct download button):

**https://github.com/yadavakash3370-stack/Downloader/releases/latest**

| APK | Size | Kab chunein |
| --- | --- | --- |
| `VideoGrab-full-arm64-v8a.apk` | ~65 MB | **Recommended** — ffmpeg bundled: best video + best audio merge, audio → m4a, har quality |
| `VideoGrab-lite-arm64-v8a.apk` | ~30 MB | Chhoti size chahiye — single-file formats |
| `VideoGrab-lite-armeabi-v7a.apk` | ~29 MB | Purane 32-bit phones |

Phone par: APK tap → "Unknown sources" allow → install.

### Full vs Lite

| Feature | Full | Lite |
| --- | --- | --- |
| Best video + best audio merge (1080p / 4K) | Yes | — |
| Single-file progressive formats | Yes | Yes |
| Audio-only extract to m4a | Yes | native audio file |
| APK size | ~65 MB | ~30 MB |

App runtime me detect karta hai ki ffmpeg hai ya nahi, isliye quality list aur format selector
apne aap build ke hisaab se ban jate hain. Settings me `Full build` / `Lite build` dikh jata hai.

**Quality note:** Lite APK me ffmpeg nahi hota, isliye sirf woh formats milte hain jinme video +
audio ek hi file me ho (aksar 360–720p). Zyada resolution chahiye to Full APK install karein.

### Build pipeline

`.github/workflows/build-apk.yml` har push (aur manual dispatch) par:

1. **Lite** arm64 + armv7 build (`videograb.withFfmpeg=false`)
2. **Full** arm64 build (ffmpeg included)
3. Artifacts upload + **Release `latest` update** with the three APKs

Stack: Flutter 3.29.3 · Dart 3 · AGP 8.7.3 · Kotlin 2.1.0 · Gradle 8.12 · Java 17 ·
minSdk 24 (Android 7.0+) · targetSdk 35.

## PW (Physics Wallah) kaise use karein

### 1. Login

- **Settings → PW account login** (ya PW tab ke neeche **Login**): mobile number daalein →
  OTP (SMS ya WhatsApp) → Login.
- OTP form kaam na kare to **PW website se login** chunein — PW tab me site par login karte hi
  app us login ko apne aap pehchan leta hai.
- Number/OTP sirf PW ke server par jate hain. Login token sirf is phone ke app storage me rehta
  hai aur sirf PW ke hosts (`pw.live`, `penpencil.co`) ko bheja jata hai. **Logout** se hat jata hai.

### 2. Lecture ka link

PW par lecture kholkar uska link copy karein (`https://www.pw.live/watch/?batchSlug=…&scheduleId=…`)
aur Download tab me paste karke **Analyze** dabayein. App aapke account se lecture kholta hai:

| Lecture ka type | Kya hota hai |
| --- | --- |
| YouTube / Vimeo par hosted | Normal download — quality chuno, Download / Play |
| Plain (unencrypted) stream | Download / Play |
| DRM-protected (Widevine) | Download **nahi** hota. "PW player me dekhein" se PW tab me chalta hai |

### 3. PW tab

Official `pw.live` site app ke andar. Lectures site ke player me chalte hain, fullscreen dabane par
landscape ho jata hai. Neeche bar me account status aur (agar page koi plain media link load kare)
**Videos** button milta hai.

> **DRM ke baare me:** PW ke zyadatar paid recorded lectures Widevine DRM se encrypted hote hain.
> Ye app decryption keys nahi nikalta aur DRM bypass nahi karta, isliye aise lectures sirf official
> player me dekhe ja sakte hain. Offline dekhne ke liye PW ki official app ka download feature use karein.

## Local build

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
# output: build/app/outputs/flutter-apk/app-release.apk
```

Android SDK 35 + JDK 17 chahiye. Build props:

```bash
-Pvideograb.abi=arm64-v8a|armeabi-v7a
-Pvideograb.withFfmpeg=true|false
```

First run par app python runtime extract karta hai (isliye pehla launch 10–20s le sakta hai).

## Project layout

```
lib/
  main.dart                       app entry + theme
  theme.dart                      neutral palette, AppCard, AppPill
  screens/
    root_shell.dart               4-tab shell
    home_screen.dart              instant detect, analyse, quality, downloads
    library_screen.dart           offline library
    player_screen.dart            video_player wrapper
    settings_screen.dart          PW account, speed, engine, storage
    study_screen.dart             PW WebView (player, fullscreen, account link)
    pw_login_screen.dart          PW OTP login
  services/
    platform_detector.dart        host-based instant detection
    engine.dart                   MethodChannel bridge
    app_links.dart                hand-off between tabs
    pw_account.dart               PW login (OTP), session, lecture link resolver
    settings_store.dart, library_store.dart
  models/                         MediaInfo, DownloadItem
  widgets/svg_icon.dart           SVG icon + button kit
android/app/src/main/kotlin/com/videograb/app/
  MainActivity.kt                 channel registration
  DownloadBridge.kt               probe / download / cancel / stream / save / delete
assets/icons/                     41 hand-written SVG icons (no emoji)
```

### Native bridge API

| Method | Args | Description |
| --- | --- | --- |
| `init` | — | python + yt-dlp + ffmpeg runtime setup |
| `probe` | `url`, `headers` | info → title, thumbnail, duration, heights, sizes, hasFfmpeg |
| `download` | `jobId, url, format, audioOnly, alsoSave, title, concurrency, headers` | yt-dlp with progress events |
| `cancel` | `jobId` | running process kill |
| `streamUrl` | `url`, `headers` | direct playable URL |
| `updateEngine` | — | latest yt-dlp |
| `saveCopy` / `deleteFile` | `path` | MediaStore export / cleanup |

Events: `progress` / `stage` / `done` / `failed` / `cancelled`.

## Libraries used

- [`youtubedl-android`](https://github.com/yausername/youtubedl-android) `0.18.1` (library + ffmpeg)
- `webview_flutter` (+ `webview_flutter_android`), `flutter_svg`, `video_player`, `shared_preferences`, `path_provider`,
  `permission_handler`
