#!/bin/bash

# Start ngrok in the background and redirect its output to a log file
# This will help in debugging if ngrok itself is failing to start
echo "Starting ngrok in background..."
./ngrok http 8000 > ngrok.log 2>&1 &

# Store the Process ID of ngrok
NGROK_PID=$!
echo "Ngrok started with PID: $NGROK_PID"

# Wait for ngrok to start and for its local API to be available
echo "Waiting for ngrok to start and expose its API..."
NGROK_API_URL="http://localhost:4040/api/tunnels"
MAX_RETRIES=15 # Increased retries
RETRY_DELAY=5 # Increased delay to give ngrok more time

for i in $(seq 1 $MAX_RETRIES); do
    # Check if ngrok process is still running
    if ! ps -p $NGROK_PID > /dev/null; then
        echo "Ngrok process died unexpectedly. Checking ngrok.log for details."
        cat ngrok.log # Print ngrok's log for debugging
        exit 1
    fi

    # Attempt to curl the ngrok API
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$NGROK_API_URL")
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Ngrok API is available (HTTP 200 OK)."
        break
    else
        echo "Ngrok API not yet available or returned status $HTTP_STATUS, retrying in $RETRY_DELAY seconds... (Attempt $i/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    fi

    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Failed to connect to ngrok API after multiple retries."
        echo "Last HTTP status received: $HTTP_STATUS"
        echo "Dumping ngrok log for further inspection:"
        cat ngrok.log # Print ngrok's log before exiting
        exit 1
    fi
done

# Get the ngrok public URL
NGROK_PUBLIC_URL=$(curl -s "$NGROK_API_URL" | jq -r '.tunnels[0].public_url')

if [ -z "$NGROK_PUBLIC_URL" ] || [ "$NGROK_PUBLIC_URL" == "null" ]; then
    echo "Failed to get ngrok public URL from API response."
    echo "Dumping full ngrok API response for debugging:"
    curl -s "$NGROK_API_URL"
    echo "Dumping ngrok log for further inspection:"
    cat ngrok.log
    exit 1
fi

echo "Ngrok Public URL: $NGROK_PUBLIC_URL"

# Export TELEGRAM_BOT_TOKEN so app.py can access it
export TELEGRAM_BOT_TOKEN=${{ secrets.TELEGRAM_BOT_TOKEN }}

# Run the Python bot, passing the ngrok URL as a command-line argument
python app.py "$NGROK_PUBLIC_URL"

# This script will exit when the python script exits, or when the GitHub Action times out.
# As GitHub Actions are not meant for persistent services, this job will eventually terminate.
