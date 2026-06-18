import os
import logging
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

# Token environment variable se lega
BOT_TOKEN = os.environ.get("BOT_TOKEN")

# Download folder
DOWNLOAD_DIR = "/tmp/downloads/"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

# States
WAITING_LINK = 1
CHOOSING_PLATFORM = 2
CHOOSING_FORMAT = 3


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [
            InlineKeyboardButton(
                "🎬 Download Shuru Karo",
                callback_data="start_download"
            )
        ],
        [
            InlineKeyboardButton(
                "ℹ️ Help",
                callback_data="help_btn"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await update.message.reply_text(
        "🎉 *Welcome to Video Downloader Bot!*\n"
        "\n"
        "Main YouTube aur Instagram se\n"
        "Video aur Music download kar sakta hoon\n"
        "\n"
        "👇 Neeche button dabao:",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return ConversationHandler.END


async def start_download(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    keyboard = [
        [
            InlineKeyboardButton(
                "❌ Cancel",
                callback_data="cancel"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await query.edit_message_text(
        "🔗 *Apna Link Bhejo:*\n"
        "\n"
        "YouTube ya Instagram ka link\n"
        "copy karke yahan paste karo 👇",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return WAITING_LINK


async def receive_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    link = update.message.text.strip()
    context.user_data['link'] = link

    keyboard = [
        [
            InlineKeyboardButton(
                "🔴 YouTube",
                callback_data="platform_youtube"
            ),
            InlineKeyboardButton(
                "📸 Instagram",
                callback_data="platform_instagram"
            )
        ],
        [
            InlineKeyboardButton(
                "❌ Cancel",
                callback_data="cancel"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await update.message.reply_text(
        "✅ *Link mil gaya!*\n"
        "\n"
        "👇 Ye kis platform ka hai?",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return CHOOSING_PLATFORM


async def choose_platform(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    platform = query.data.replace("platform_", "")
    context.user_data['platform'] = platform

    if platform == "youtube":
        name = "YouTube"
    else:
        name = "Instagram"

    keyboard = [
        [
            InlineKeyboardButton(
                "🎵 MP3 (Audio Only)",
                callback_data="format_mp3"
            )
        ],
        [
            InlineKeyboardButton(
                "🎬 MP4 (Video)",
                callback_data="format_mp4"
            )
        ],
        [
            InlineKeyboardButton(
                "❌ Cancel",
                callback_data="cancel"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await query.edit_message_text(
        f"✅ *Platform:* {name}\n"
        "\n"
        "👇 Kaunsa format chahiye?",
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
                # Agar exact name na mile toh dhundo
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

    if platform == "youtube":
        pname = "YouTube"
    else:
        pname = "Instagram"

    if fmt == "mp3":
        fname = "🎵 MP3 Audio"
    else:
        fname = "🎬 MP4 Video"

    await query.edit_message_text(
        "⏳ *Downloading... Please Wait*\n"
        "\n"
        f"📱 Platform: {pname}\n"
        f"📁 Format: {fname}\n"
        "\n"
        "⏱ Thoda time lagega...",
        parse_mode='Markdown'
    )

    filepath, title, error = do_download(link, fmt)

    if error or filepath is None:
        keyboard = [
            [
                InlineKeyboardButton(
                    "🔄 Dobara Try Karo",
                    callback_data="start_download"
                )
            ],
            [
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="go_home"
                )
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        err_msg = error if error else "File not found"
        await query.edit_message_text(
            "❌ *Download Failed!*\n"
            "\n"
            f"Error: {err_msg[:200]}\n"
            "\n"
            "🔹 Link check karo\n"
            "🔹 Dobara try karo",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        return ConversationHandler.END

    if not os.path.exists(filepath):
        keyboard = [
            [
                InlineKeyboardButton(
                    "🔄 Retry",
                    callback_data="start_download"
                )
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            "❌ *File nahi mili!*\n"
            "Dobara try karo",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        return ConversationHandler.END

    file_size = os.path.getsize(filepath)
    size_mb = round(file_size / (1024 * 1024), 1)

    if size_mb > 50:
        keyboard = [
            [
                InlineKeyboardButton(
                    "🔄 Chhota Video Try",
                    callback_data="start_download"
                )
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            f"❌ *File bahut badi hai!*\n"
            f"📁 Size: {size_mb} MB\n"
            f"📌 Limit: 50 MB",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )
        os.remove(filepath)
        return ConversationHandler.END

    await query.edit_message_text(
        f"📤 *Uploading...*\n"
        f"📁 Size: {size_mb} MB",
        parse_mode='Markdown'
    )

    try:
        if fmt == "mp3":
            with open(filepath, 'rb') as f:
                await query.message.reply_audio(
                    audio=f,
                    title=title,
                    caption=(
                        f"🎵 *{title}*\n\n"
                        f"📱 {pname} | 📁 MP3\n"
                        f"📦 {size_mb} MB"
                    ),
                    parse_mode='Markdown'
                )
        else:
            with open(filepath, 'rb') as f:
                await query.message.reply_video(
                    video=f,
                    caption=(
                        f"🎬 *{title}*\n\n"
                        f"📱 {pname} | 📁 MP4\n"
                        f"📦 {size_mb} MB"
                    ),
                    parse_mode='Markdown',
                    supports_streaming=True
                )

        keyboard = [
            [
                InlineKeyboardButton(
                    "🎬 Aur Download Karo",
                    callback_data="start_download"
                )
            ],
            [
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="go_home"
                )
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            "✅ *Download Complete!*\n"
            "\n"
            f"📌 {title}\n"
            f"📱 {pname}\n"
            f"📁 {fname}\n"
            f"📦 {size_mb} MB\n"
            "\n"
            "👇 Aur download karna hai?",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )

    except Exception as e:
        keyboard = [
            [
                InlineKeyboardButton(
                    "🔄 Retry",
                    callback_data="start_download"
                )
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)

        await query.edit_message_text(
            f"❌ *Upload failed!*\n"
            f"Error: {str(e)[:150]}",
            reply_markup=reply_markup,
            parse_mode='Markdown'
        )

    # Clean up
    try:
        os.remove(filepath)
    except:
        pass

    # Puri downloads folder saaf karo
    try:
        for f in os.listdir(DOWNLOAD_DIR):
            fp = os.path.join(DOWNLOAD_DIR, f)
            os.remove(fp)
    except:
        pass

    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    keyboard = [
        [
            InlineKeyboardButton(
                "🎬 Download Shuru Karo",
                callback_data="start_download"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await query.edit_message_text(
        "❌ *Cancelled!*\n"
        "\n"
        "Jab chahein dobara try karo 👇",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return ConversationHandler.END


async def go_home(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    keyboard = [
        [
            InlineKeyboardButton(
                "🎬 Download Shuru Karo",
                callback_data="start_download"
            )
        ],
        [
            InlineKeyboardButton(
                "ℹ️ Help",
                callback_data="help_btn"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await query.edit_message_text(
        "🎉 *Video Downloader Bot*\n"
        "\n"
        "👇 Button dabao:",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )
    return ConversationHandler.END


async def help_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    keyboard = [
        [
            InlineKeyboardButton(
                "🎬 Download Shuru Karo",
                callback_data="start_download"
            )
        ],
        [
            InlineKeyboardButton(
                "🏠 Home",
                callback_data="go_home"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await query.edit_message_text(
        "📖 *Kaise Use Kare:*\n"
        "\n"
        "1️⃣ Download Shuru Karo dabao\n"
        "2️⃣ Link paste karo\n"
        "3️⃣ YouTube ya Instagram select karo\n"
        "4️⃣ MP3 ya MP4 select karo\n"
        "5️⃣ File aa jayegi!\n"
        "\n"
        "⚠️ Max size: 50MB",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )


async def unknown(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [
            InlineKeyboardButton(
                "🎬 Download Shuru Karo",
                callback_data="start_download"
            )
        ]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    await update.message.reply_text(
        "🤔 Pehle button dabao phir link bhejo 👇",
        reply_markup=reply_markup,
        parse_mode='Markdown'
    )


def main():
    print("🤖 Bot Starting on Render...")

    app = Application.builder().token(BOT_TOKEN).build()

    conv = ConversationHandler(
        entry_points=[
            CallbackQueryHandler(
                start_download,
                pattern="^start_download$"
            )
        ],
        states={
            WAITING_LINK: [
                MessageHandler(
                    filters.TEXT & ~filters.COMMAND,
                    receive_link
                )
            ],
            CHOOSING_PLATFORM: [
                CallbackQueryHandler(
                    choose_platform,
                    pattern="^platform_"
                )
            ],
            CHOOSING_FORMAT: [
                CallbackQueryHandler(
                    choose_format,
                    pattern="^format_"
                )
            ],
        },
        fallbacks=[
            CallbackQueryHandler(cancel, pattern="^cancel$"),
            CommandHandler("start", start),
        ],
        per_message=False,
    )

    app.add_handler(CommandHandler("start", start))
    app.add_handler(conv)
    app.add_handler(
        CallbackQueryHandler(go_home, pattern="^go_home$")
    )
    app.add_handler(
        CallbackQueryHandler(help_btn, pattern="^help_btn$")
    )
    app.add_handler(
        MessageHandler(
            filters.TEXT & ~filters.COMMAND,
            unknown
        )
    )

    print("✅ Bot is RUNNING on Render!")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
