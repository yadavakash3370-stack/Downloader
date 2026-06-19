import os
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from telegram import (
    Update,
    InlineKeyboardButton,
    InlineKeyboardMarkup
)
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    MessageHandler,
    filters,
    ContextTypes,
    ConversationHandler
)
import yt_dlp

logging.basicConfig(
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

BOT_TOKEN = os.environ.get("BOT_TOKEN")

DOWNLOAD_DIR = "/tmp/downloads/"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

WAITING_LINK = 1
CHOOSING_PLATFORM = 2
CHOOSING_FORMAT = 3


# ==========================================
# DUMMY WEB SERVER (Render port ke liye)
# ==========================================
class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b"<h1>Bot is Running!</h1>")
    
    def log_message(self, format, *args):
        return

def run_web_server():
    port = int(os.environ.get("PORT", 10000))
    server = HTTPServer(('0.0.0.0', port), HealthHandler)
    print(f"🌐 Web server running on port {port}")
    server.serve_forever()


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [InlineKeyboardButton("🎬 Download Shuru Karo", callback_data="start_download")],
        [InlineKeyboardButton("ℹ️ Help", callback_data="help_btn")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        "🎉 *Welcome to Video Downloader Bot!*\n\n👇 Neeche button dabao:",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return ConversationHandler.END


async def start_download(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    keyboard = [[InlineKeyboardButton("❌ Cancel", callback_data="cancel")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "🔗 *Apna Link Bhejo:*\n\nYouTube ya Instagram link paste karo 👇",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return WAITING_LINK


async def receive_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    link = update.message.text.strip()
    context.user_data['link'] = link
    keyboard = [
        [
            InlineKeyboardButton("🔴 YouTube", callback_data="platform_youtube"),
            InlineKeyboardButton("📸 Instagram", callback_data="platform_instagram")
        ],
        [InlineKeyboardButton("❌ Cancel", callback_data="cancel")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text(
        "✅ *Link mil gaya!*\n\n👇 Ye kis platform ka hai?",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return CHOOSING_PLATFORM


async def choose_platform(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    platform = query.data.replace("platform_", "")
    context.user_data['platform'] = platform
    name = "YouTube" if platform == "youtube" else "Instagram"
    keyboard = [
        [InlineKeyboardButton("🎵 MP3 (Audio)", callback_data="format_mp3")],
        [InlineKeyboardButton("🎬 MP4 (Video)", callback_data="format_mp4")],
        [InlineKeyboardButton("❌ Cancel", callback_data="cancel")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        f"✅ *Platform:* {name}\n\n👇 Format select karo?",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return CHOOSING_FORMAT


def do_download(link, fmt):
    try:
        if fmt == "mp3":
            opts = {
                'format': 'bestaudio/best',
                'outtmpl': DOWNLOAD_DIR + '%(title)s.%(ext)s',
                'postprocessors': [{
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'mp3',
                    'preferredquality': '192',
                }],
                'noplaylist': True,
                'quiet': True,
            }
        else:
            opts = {
                'format': 'best[ext=mp4][filesize<50M]/best[ext=mp4]/best',
                'outtmpl': DOWNLOAD_DIR + '%(title)s.%(ext)s',
                'noplaylist': True,
                'quiet': True,
            }
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(link, download=True)
            title = info.get('title', 'video')
            if fmt == "mp3":
                filepath = DOWNLOAD_DIR + title + ".mp3"
                if not os.path.exists(filepath):
                    for f in os.listdir(DOWNLOAD_DIR):
                        if f.endswith('.mp3'):
                            filepath = DOWNLOAD_DIR + f
                            break
            else:
                filepath = ydl.prepare_filename(info)
                if not os.path.exists(filepath):
                    for f in os.listdir(DOWNLOAD_DIR):
                        if f.endswith('.mp4') or f.endswith('.webm'):
                            filepath = DOWNLOAD_DIR + f
                            break
            return filepath, title, None
    except Exception as e:
        return None, None, str(e)


async def choose_format(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    fmt = query.data.replace("format_", "")
    link = context.user_data.get('link', '')
    platform = context.user_data.get('platform', '')
    pname = "YouTube" if platform == "youtube" else "Instagram"
    fname = "🎵 MP3" if fmt == "mp3" else "🎬 MP4"

    await query.edit_message_text(
        f"⏳ *Downloading...*\n\n📱 {pname}\n📁 {fname}\n\n⏱ Wait karo...",
        parse_mode='Markdown'
    )
    filepath, title, error = do_download(link, fmt)

    if error or filepath is None or not os.path.exists(filepath):
        keyboard = [[InlineKeyboardButton("🔄 Retry", callback_data="start_download")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        err = error if error else "File not found"
        await query.edit_message_text(
            f"❌ *Failed!*\n\nError: {err[:200]}",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        return ConversationHandler.END

    size_mb = round(os.path.getsize(filepath) / (1024 * 1024), 1)
    if size_mb > 50:
        keyboard = [[InlineKeyboardButton("🔄 Retry", callback_data="start_download")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            f"❌ *File badi hai!* {size_mb} MB\nLimit: 50 MB",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        os.remove(filepath)
        return ConversationHandler.END

    await query.edit_message_text(f"📤 *Uploading...* {size_mb} MB", parse_mode='Markdown')

    try:
        if fmt == "mp3":
            with open(filepath, 'rb') as f:
                await query.message.reply_audio(
                    audio=f, title=title,
                    caption=f"🎵 *{title}*\n📱 {pname} | 📦 {size_mb} MB",
                    parse_mode='Markdown'
                )
        else:
            with open(filepath, 'rb') as f:
                await query.message.reply_video(
                    video=f,
                    caption=f"🎬 *{title}*\n📱 {pname} | 📦 {size_mb} MB",
                    parse_mode='Markdown',
                    supports_streaming=True
                )
        keyboard = [
            [InlineKeyboardButton("🎬 Aur Download", callback_data="start_download")],
            [InlineKeyboardButton("🏠 Home", callback_data="go_home")]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            f"✅ *Complete!*\n\n📌 {title}\n📦 {size_mb} MB",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
    except Exception as e:
        keyboard = [[InlineKeyboardButton("🔄 Retry", callback_data="start_download")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(
            f"❌ Upload failed: {str(e)[:150]}",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )

    try:
        for f in os.listdir(DOWNLOAD_DIR):
            os.remove(os.path.join(DOWNLOAD_DIR, f))
    except:
        pass
    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    keyboard = [[InlineKeyboardButton("🎬 Start", callback_data="start_download")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text("❌ Cancelled!", reply_markup=reply_markup)
    return ConversationHandler.END


async def go_home(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🎬 Download Shuru Karo", callback_data="start_download")],
        [InlineKeyboardButton("ℹ️ Help", callback_data="help_btn")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text("🎉 *Video Downloader Bot*\n\n👇 Button dabao:",
        reply_markup=reply_markup, parse_mode='Markdown')
    return ConversationHandler.END


async def help_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    keyboard = [
        [InlineKeyboardButton("🎬 Start", callback_data="start_download")],
        [InlineKeyboardButton("🏠 Home", callback_data="go_home")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await query.edit_message_text(
        "📖 *Kaise Use Kare:*\n\n1️⃣ Start dabao\n2️⃣ Link bhejo\n3️⃣ Platform choose\n4️⃣ Format choose\n5️⃣ Done!",
        reply_markup=reply_markup, parse_mode='Markdown')


async def unknown(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [[InlineKeyboardButton("🎬 Start", callback_data="start_download")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text("🤔 Pehle button dabao 👇", reply_markup=reply_markup)


def main():
    print("🤖 Bot Starting...")
    
    # Web server alag thread me chalao
    web_thread = threading.Thread(target=run_web_server, daemon=True)
    web_thread.start()
    
    app = Application.builder().token(BOT_TOKEN).build()
    conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(start_download, pattern="^start_download$")],
        states={
            WAITING_LINK: [MessageHandler(filters.TEXT & ~filters.COMMAND, receive_link)],
            CHOOSING_PLATFORM: [CallbackQueryHandler(choose_platform, pattern="^platform_")],
            CHOOSING_FORMAT: [CallbackQueryHandler(choose_format, pattern="^format_")],
        },
        fallbacks=[
            CallbackQueryHandler(cancel, pattern="^cancel$"),
            CommandHandler("start", start),
        ],
        per_message=False,
    )
    app.add_handler(CommandHandler("start", start))
    app.add_handler(conv)
    app.add_handler(CallbackQueryHandler(go_home, pattern="^go_home$"))
    app.add_handler(CallbackQueryHandler(help_btn, pattern="^help_btn$"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, unknown))
    print("✅ Bot RUNNING!")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
