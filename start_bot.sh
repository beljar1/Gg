#!/bin/bash

# কোনো কমান্ড ব্যর্থ হলে স্ক্রিপ্টটি অবিলম্বে বন্ধ হয়ে যাবে।
set -e

echo "ব্যাকগ্রাউন্ডে ngrok শুরু হচ্ছে..."
# ngrok ব্যাকগ্রাউন্ডে শুরু করুন, এর stdout এবং stderr একটি লগ ফাইলে রিডাইরেক্ট করুন।
./ngrok http 8000 > ngrok.log 2>&1 &

# ngrok প্রক্রিয়ার PID (Process ID) সংরক্ষণ করুন।
NGROK_PID=$!
echo "Ngrok PID সহ শুরু হয়েছে: $NGROK_PID"

# ngrok শুরু হওয়ার এবং এর লোকাল API উপলব্ধ হওয়ার জন্য অপেক্ষা করুন।
echo "ngrok শুরু হওয়ার এবং এর API উন্মুক্ত করার জন্য অপেক্ষা করছি..."
NGROK_API_URL="http://localhost:4040/api/tunnels"
MAX_RETRIES=30 # সর্বোচ্চ ৩০ বার চেষ্টা করা হবে।
RETRY_DELAY=5 # প্রতি ৫ সেকেন্ডে পুনরায় চেষ্টা করা হবে।

for i in $(seq 1 $MAX_RETRIES); do
    # ngrok প্রক্রিয়া এখনও চলছে কিনা তা পরীক্ষা করুন।
    if ! ps -p $NGROK_PID > /dev/null; then
        echo "Ngrok প্রক্রিয়া অপ্রত্যাশিতভাবে বন্ধ হয়ে গেছে।"
        echo "বিস্তারিত জানার জন্য ngrok.log দেখা হচ্ছে:"
        cat ngrok.log # ডিবাগিংয়ের জন্য ngrok-এর লগ প্রিন্ট করুন।
        exit 1
    fi

    # ngrok API-কে কার্ল করার চেষ্টা করুন।
    # ডিবাগিংয়ের জন্য সম্পূর্ণ প্রতিক্রিয়া সংরক্ষণ করুন।
    NGROK_API_RESPONSE=$(curl -s "$NGROK_API_URL")
    # HTTP স্ট্যাটাস কোড বের করুন।
    HTTP_STATUS=$(echo "$NGROK_API_RESPONSE" | head -n 1 | grep -oP 'HTTP/\d\.\d \K\d{3}')

    if [ -z "$HTTP_STATUS" ]; then
        # যদি কোনো HTTP স্ট্যাটাস না থাকে, তাহলে কার্ল সংযোগ করতে ব্যর্থ হয়েছে বা প্রতিক্রিয়া খালি/ত্রুটিপূর্ণ।
        echo "Ngrok API এখনও উপলব্ধ নয় বা একটি খালি/ত্রুটিপূর্ণ প্রতিক্রিয়া দিয়েছে (চেষ্টা $i/$MAX_RETRIES)।"
        echo "সম্পূর্ণ API প্রতিক্রিয়া (যদি থাকে):"
        echo "$NGROK_API_RESPONSE"
        sleep $RETRY_DELAY
    elif [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Ngrok API উপলব্ধ (HTTP 200 OK)।"
        # প্রতিক্রিয়াতে 'tunnels' অ্যারে আছে এবং এটি খালি নয় তা পরীক্ষা করুন।
        if echo "$NGROK_API_RESPONSE" | jq -e '.tunnels | length > 0' > /dev/null; then
            echo "Ngrok API প্রতিক্রিয়াতে সক্রিয় টানেল রয়েছে।"
            break # API প্রস্তুত এবং টানেল বিদ্যমান থাকলে লুপ থেকে বেরিয়ে আসুন।
        else
            echo "Ngrok API 200 OK, কিন্তু এখনও কোনো টানেল পাওয়া যায়নি, $RETRY_DELAY সেকেন্ড পরে আবার চেষ্টা করছি... (চেষ্টা $i/$MAX_RETRIES)"
            echo "সম্পূর্ণ API প্রতিক্রিয়া:"
            echo "$NGROK_API_RESPONSE"
            sleep $RETRY_DELAY
        fi
    else
        echo "Ngrok API স্ট্যাটাস $HTTP_STATUS ফেরত দিয়েছে, $RETRY_DELAY সেকেন্ড পরে আবার চেষ্টা করছি... (চেষ্টা $i/$MAX_RETRIES)"
        echo "সম্পূর্ণ API প্রতিক্রিয়া:"
        echo "$NGROK_API_RESPONSE"
        sleep $RETRY_DELAY
    fi

    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "অনেকবার চেষ্টার পরেও ngrok API-এর সাথে সংযোগ করতে বা সক্রিয় টানেল পেতে ব্যর্থ হয়েছে।"
        echo "শেষ প্রাপ্ত HTTP স্ট্যাটাস: $HTTP_STATUS"
        echo "শেষ সম্পূর্ণ ngrok API প্রতিক্রিয়া:"
        echo "$NGROK_API_RESPONSE"
        echo "আরও পরিদর্শনের জন্য ngrok লগ দেখা হচ্ছে:"
        cat ngrok.log # বেরিয়ে আসার আগে ngrok-এর লগ প্রিন্ট করুন।
        exit 1
    fi
done

# ngrok পাবলিক URL পান।
# raw স্ট্রিং আউটপুট পেতে এবং সম্ভাব্য null মানগুলি সঠিকভাবে পরিচালনা করতে 'jq -r' ব্যবহার করুন।
NGROK_PUBLIC_URL=$(echo "$NGROK_API_RESPONSE" | jq -r '.tunnels[0].public_url // empty')

if [ -z "$NGROK_PUBLIC_URL" ]; then
    echo "API প্রতিক্রিয়া থেকে ngrok পাবলিক URL পেতে ব্যর্থ হয়েছে (URL খালি বা null ছিল)।"
    echo "ডিবাগিংয়ের জন্য সম্পূর্ণ ngrok API প্রতিক্রিয়া দেখা হচ্ছে:"
    echo "$NGROK_API_RESPONSE"
    echo "আরও পরিদর্শনের জন্য ngrok লগ দেখা হচ্ছে:"
    cat ngrok.log
    exit 1
fi

echo "Ngrok পাবলিক URL: $NGROK_PUBLIC_URL"

# app.py যাতে এটি অ্যাক্সেস করতে পারে তার জন্য TELEGRAM_BOT_TOKEN এক্সপোর্ট করুন।
# নিশ্চিত করুন যে এই গোপনীয়তা GitHub Actions-এ সঠিকভাবে কনফিগার করা আছে।
export TELEGRAM_BOT_TOKEN="${{ secrets.TELEGRAM_BOT_TOKEN }}"

# ngrok URL কে কমান্ড-লাইন আর্গুমেন্ট হিসাবে পাস করে পাইথন বট চালান।
# বর্তমান শেলকে পাইথন প্রক্রিয়া দ্বারা প্রতিস্থাপন করতে 'exec' ব্যবহার করুন।
exec python app.py "$NGROK_PUBLIC_URL"

# এই স্ক্রিপ্টটি পাইথন স্ক্রিপ্ট বন্ধ হলে বা GitHub অ্যাকশন টাইম আউট হলে বন্ধ হয়ে যাবে।
# যেহেতু GitHub অ্যাকশনগুলি স্থায়ী পরিষেবার জন্য নয়, তাই এই কাজটি শেষ পর্যন্ত বন্ধ হয়ে যাবে।
