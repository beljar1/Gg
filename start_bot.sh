#!/bin/bash

# --- এনভায়রনমেন্ট ভেরিয়েবল চেক করা ---
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "Error: TELEGRAM_BOT_TOKEN is not set."
  exit 1
fi

if [ -z "$PORT" ]; then
  echo "Error: PORT is not set."
  exit 1
fi

echo "TELEGRAM_BOT_TOKEN (first 5 chars): ${TELEGRAM_BOT_TOKEN:0:5}..."
echo "Bot will run on port: $PORT"

# --- 1. আপনার পাইথন বট শুরু করা ---
echo "Starting your Python bot..."
# নিশ্চিত করুন যে আপনার বটটি আপনার উল্লেখিত পোর্টে (যেমন 8000) লিসেন করছে।
# 'your_bot_main_file.py' আপনার বটের মূল ফাইলের নাম দিয়ে প্রতিস্থাপন করুন।
# '&' ব্যবহার করে বটটিকে ব্যাকগ্রাউন্ডে চালান যাতে স্ক্রিপ্টটি চলতে পারে।
python your_bot_main_file.py &
BOT_PID=$! # বটের প্রসেস ID সেভ করুন

# বট শুরু হতে কিছু সময় দিন
echo "Waiting for bot to start on port $PORT..."
sleep 5 # 5 সেকেন্ড অপেক্ষা করুন

# --- 2. ngrok টানেল শুরু করা এবং URL পাওয়া ---
echo "Starting ngrok tunnel..."
# ngrok এর সমস্ত আউটপুট একটি লগ ফাইলে সেভ করুন।
# --log=stdout নিশ্চিত করে যে লগ stdout এ যাবে, যা আমরা ফাইলে রিডাইরেক্ট করছি।
./ngrok http "$PORT" --log=stdout > ngrok_output.log 2>&1 &
NGROK_PID=$! # ngrok প্রসেস ID সেভ করুন

# ngrok কে টানেল তৈরি করতে কিছুটা সময় দিন
echo "Waiting for ngrok to establish tunnel..."
sleep 10 # 10 সেকেন্ড অপেক্ষা করুন, প্রয়োজনে এটি বাড়াতে পারেন

# ngrok আউটপুট ফাইল থেকে পাবলিক URL পার্স করার চেষ্টা করুন
echo "Attempting to extract ngrok URL from ngrok_output.log..."
NGROK_URL=$(grep -o 'url=https://[^ ]*' ngrok_output.log | head -n 1 | cut -d'=' -f2)

# --- 3. URL পাওয়ার ক্ষেত্রে ত্রুটি হ্যান্ডলিং ---
if [ -z "$NGROK_URL" ]; then
  echo "Error: Failed to get ngrok public URL."
  echo "ngrok_output.log content:"
  cat ngrok_output.log # ডিবাগ করার জন্য লগের কন্টেন্ট প্রিন্ট করুন
  kill $BOT_PID # বট প্রক্রিয়াটি বন্ধ করুন
  kill $NGROK_PID # ngrok প্রক্রিয়াটি বন্ধ করুন
  exit 1 # ব্যর্থতার কোড দিয়ে এক্সিট করুন
fi

echo "Successfully got Ngrok URL: $NGROK_URL"

# --- 4. টেলিগ্রাম ওয়েবহুক সেট করা (যদি আপনার বট ওয়েবহুক ব্যবহার করে) ---
echo "Setting Telegram webhook..."
# নিশ্চিত করুন যে আপনার ওয়েবহুক URL সঠিক পাথ (যেমন /webhook) ব্যবহার করছে।
curl -F "url=$NGROK_URL/webhook" https://api.telegram.org/bot"$TELEGRAM_BOT_TOKEN"/setWebhook

echo "Webhook command executed."

# --- 5. স্ক্রিপ্টকে চালু রাখা ---
# GitHub Actions রানার বন্ধ হয়ে গেলে বটও বন্ধ হয়ে যাবে।
# এই স্ক্রিপ্টটি একটি দীর্ঘস্থায়ী প্রক্রিয়া না হলে GitHub Actions কাজটি শেষ করবে।
# যদি আপনি বটটিকে চালু রাখতে চান, তাহলে এই স্ক্রিপ্টটি এখানে "exit" করবে না
# বরং এটি বট এবং ngrok প্রক্রিয়াগুলোকে সচল রাখবে।
# তবে, মনে রাখবেন GitHub Actions মূলত CI/CD এর জন্য, হোস্টিং এর জন্য নয়।
# আপনার বটকে ২৪/৭ সচল রাখতে হলে একটি প্রকৃত হোস্টিং সার্ভিস ব্যবহার করা উচিত।

# এই স্ক্রিপ্টটি সফলভাবে এক্সিকিউট হলে (যদি বট ব্যাকগ্রাউন্ডে চলে),
# তাহলে অ্যাকশন সফল হিসেবে শেষ হবে।
# কিন্তু বট আসলে রানারে চলতে থাকবে যতক্ষণ না রানার বন্ধ হয়।
# রানার একটি নির্দিষ্ট সময় পর (সাধারণত 6 ঘন্টা) বন্ধ হয়ে যায়।

echo "Bot deployment script finished."
