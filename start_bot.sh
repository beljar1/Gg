#!/bin/bash

# Start ngrok in the background
# ngrok will now automatically use the authtoken configured in ~/.ngrok2/ngrok.yml
./ngrok http 8000 > /dev/null &

# Wait for ngrok to start and for its local API to be available
# We'll try to connect to the ngrok API endpoint in a loop
echo "Waiting for ngrok to start and expose its API..."
NGROK_API_URL="http://localhost:4040/api/tunnels"
MAX_RETRIES=10
RETRY_DELAY=3 # seconds

for i in $(seq 1 $MAX_RETRIES); do
    if curl -s "$NGROK_API_URL" > /dev/null; then
        echo "Ngrok API is available."
        break
    else
        echo "Ngrok API not yet available, retrying in $RETRY_DELAY seconds... (Attempt $i/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "Failed to connect to ngrok API after multiple retries. Exiting."
        exit 1
    fi
done

# Get the ngrok public URL
NGROK_PUBLIC_URL=$(curl -s "$NGROK_API_URL" | jq -r '.tunnels[0].public_url')

if [ -z "$NGROK_PUBLIC_URL" ] || [ "$NGROK_PUBLIC_URL" == "null" ]; then
    echo "Failed to get ngrok public URL from API response. Exiting."
    # Optionally, print the full ngrok API response for debugging
    # curl -s "$NGROK_API_URL"
    exit 1
fi

echo "Ngrok Public URL: $NGROK_PUBLIC_URL"

# Export TELEGRAM_BOT_TOKEN so app.py can access it
# This variable is already available in the GitHub Actions environment from secrets
export TELEGRAM_BOT_TOKEN=${{ secrets.TELEGRAM_BOT_TOKEN }}

# Run the Python bot, passing the ngrok URL as a command-line argument
python app.py "$NGROK_PUBLIC_URL"

# This script will exit when the python script exits, or when the GitHub Action times out.
# As GitHub Actions are not meant for persistent services, this job will eventually terminate.
