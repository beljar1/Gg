#!/bin/bash

# কোনো কমান্ড ব্যর্থ হলে স্ক্রিপ্টটি অবিলম্বে বন্ধ হয়ে যাবে।
set -e

echo "Starting ngrok in background..."
# ngrok ব্যাকগ্রাউন্ডে শুরু করুন, এর আউটপুট একটি লগ ফাইলে রিডাইরেক্ট করুন।
./ngrok http 8000 > ngrok.log 2>&1 &

# ngrok প্রক্রিয়ার PID (Process ID) সংরক্ষণ করুন।
NGROK_PID=$!
echo "Ngrok started with PID: $NGROK_PID"

# ngrok শুরু হওয়ার এবং এর লোকাল API উপলব্ধ হওয়ার জন্য অপেক্ষা করুন।
echo "Waiting for ngrok to start and expose its API..."
NGROK_API_URL="http://localhost:4040/api/tunnels"
MAX_RETRIES=30 # সর্বোচ্চ ৩০ বার চেষ্টা করা হবে।
RETRY_DELAY=5 # প্রতি ৫ সেকেন্ডে পুনরায় চেষ্টা করা হবে।

for i in $(seq 1 $MAX_RETRIES); do
    # ngrok প্রক্রিয়া এখনও চলছে কিনা তা পরীক্ষা করুন।
    if ! ps -p $NGROK_PID > /dev/null; then
        echo "Ngrok process died unexpectedly."
        echo "Dumping ngrok.log for details:"
        cat ngrok.log # ডিবাগিংয়ের জন্য ngrok-এর লগ প্রিন্ট করুন।
        exit 1
    fi

    # ngrok API-কে কার্ল করার চেষ্টা করুন।
    # ডিবাগিংয়ের জন্য সম্পূর্ণ প্রতিক্রিয়া সংরক্ষণ করুন।
    NGROK_API_RESPONSE=$(curl -s "$NGROK_API_URL")
    HTTP_STATUS=$(echo "$NGROK_API_RESPONSE" | head -n 1 | grep -oP 'HTTP/\d\.\d \K\d{3}') # HTTP স্ট্যাটাস কোড বের করুন।

    if [ -z "$HTTP_STATUS" ]; then
        # যদি কোনো HTTP স্ট্যাটাস না থাকে, তাহলে কার্ল সংযোগ করতে ব্যর্থ হয়েছে বা প্রতিক্রিয়া খালি/ত্রুটিপূর্ণ।
        echo "Ngrok API not yet available or returned an empty/malformed response (Attempt $i/$MAX_RETRIES)."
        echo "Full API response (if any):"
        echo "$NGROK_API_RESPONSE"
        sleep $RETRY_DELAY
    elif [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Ngrok API is available (HTTP 200 OK)."
        # প্রতিক্রিয়াতে 'tunnels' অ্যারে আছে এবং এটি খালি নয় তা পরীক্ষা করুন।
        if echo "$NGROK_API_RESPONSE" | jq -e '.tunnels | length > 0' > /dev/null; then
            echo "Ngrok API response contains active tunnels."
            break # API প্রস্তুত এবং টানেল বিদ্যমান থাকলে লুপ থেকে বেরিয়ে আসুন।
        else
            echo "Ngrok API is 200 OK, but no tunnels found yet, retrying in $RETRY_DELAY seconds... (Attempt $i/$MAX_RETRIES)"
            echo "Full API response:"
            echo "$NGROK_API_RESPONSE"
            sleep $RETRY_DELAY
        fi
    else
        echo "Ngrok API returned status $HTTP_STATUS, retrying in $RETRY_DELAY seconds... (Attempt $i/$MAX_RETRIES)"
        echo "Full API response:"
        echo "$NGROK_API_RESPONSE"
        sleep $RETRY_DELAY
    fi

    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Failed to connect to ngrok API or get active tunnels after multiple retries."
        echo "Last HTTP status received: $HTTP_STATUS"
        echo "Last full ngrok API response:"
        echo "$NGROK_API_RESPONSE"
        echo "Dumping ngrok log for further inspection:"
        cat ngrok.log # বেরিয়ে আসার আগে ngrok-এর লগ প্রিন্ট করুন।
        exit 1
    fi
done

# ngrok পাবলিক URL পান।
# raw স্ট্রিং আউটপুট পেতে এবং সম্ভাব্য null মানগুলি সঠিকভাবে পরিচালনা করতে 'jq -r' ব্যবহার করুন।
NGROK_PUBLIC_URL=$(echo "$NGROK_API_RESPONSE" | jq -r '.tunnels[0].public_url // empty')

if [ -z "$NGROK_PUBLIC_URL" ]; then
    echo "Failed to get ngrok public URL from API response (URL was empty or null)."
    echo "Dumping full ngrok API response for debugging:"
    echo "$NGROK_API_RESPONSE"
    echo "Dumping ngrok log for further inspection:"
    cat ngrok.log
    exit 1
fi

echo "Ngrok Public URL: $NGROK_PUBLIC_URL"

# app.py যাতে এটি অ্যাক্সেস করতে পারে তার জন্য TELEGRAM_BOT_TOKEN এক্সপোর্ট করুন।
# নিশ্চিত করুন যে এই গোপনীয়তা GitHub Actions-এ সঠিকভাবে কনফিগার করা আছে।
export TELEGRAM_BOT_TOKEN="${{ secrets.TELEGRAM_BOT_TOKEN }}"

# ngrok URL কে কমান্ড-লাইন আর্গুমেন্ট হিসাবে পাস করে পাইথন বট চালান।
# বর্তমান শেলকে পাইথন প্রক্রিয়া দ্বারা প্রতিস্থাপন করতে 'exec' ব্যবহার করুন।
exec python app.py "$NGROK_PUBLIC_URL"

# এই স্ক্রিপ্টটি পাইথন স্ক্রিপ্ট বন্ধ হলে বা GitHub অ্যাকশন টাইম আউট হলে বন্ধ হয়ে যাবে।
# যেহেতু GitHub অ্যাকশনগুলি স্থায়ী পরিষেবার জন্য নয়, তাই এই কাজটি শেষ পর্যন্ত বন্ধ হয়ে যাবে।
