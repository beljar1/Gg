import random
import os
import sys
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters

user_agents_us = [
    "Mozilla/5.0 (Linux; U; Android {ver}; en-us; Nexus One Build/FRF91) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1",
    "Mozilla/5.0 (Linux; U; Android {ver}; en-us; GT-I9100 Build/IMM76D) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30",
    "Mozilla/5.0 (Linux; U; Android {ver}; en-us; LG-E400 Build/LRX21Y) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30",
    "Mozilla/5.0 (iPhone; CPU iPhone OS {ver}_1 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13B143 Safari/601.1",
    "Mozilla/5.0 (iPhone; CPU iPhone OS {ver}_0 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13B143 Safari/601.1",
]

def generate_us_user_agent():
    template = random.choice(user_agents_us)
    version = random.randint(10, 15)
    return template.format(ver=version)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text('Hi! Use /ua to get a random US-based user agent.')

async def get_user_agent(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    ua = generate_us_user_agent()
    await update.message.reply_text(f'Here is a random US-based user agent:\n\n`{ua}`', parse_mode='MarkdownV2')

async def echo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(update.message.text)

def main() -> None:
    TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
    if not TELEGRAM_BOT_TOKEN:
        print("Error: TELEGRAM_BOT_TOKEN not found in environment variables.")
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Error: Ngrok public URL not provided as a command-line argument.")
        sys.exit(1)

    NGROK_PUBLIC_URL = sys.argv[1]
    PORT = int(os.getenv("PORT", "8000"))

    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("ua", get_user_agent))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))

    webhook_path = f"/telegram-bot/{TELEGRAM_BOT_TOKEN}"
    full_webhook_url = f"{NGROK_PUBLIC_URL}{webhook_path}"
    print(f"Setting webhook to: {full_webhook_url}")

    application.run_webhook(
        listen="0.0.0.0",
        port=PORT,
        url_path=webhook_path,
        webhook_url=full_webhook_url
    )

if __name__ == "__main__":
    main()
