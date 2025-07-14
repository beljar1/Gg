#!/bin/bash

# Start ngrok in the background
# ngrok will now automatically use the authtoken configured in ~/.ngrok2/ngrok.yml
./ngrok http 8000 > /dev/null &

# Wait for ngrok to start and get the public URL
sleep 5 # Give ngrok some time to establish the tunnel
NGROK_PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')

if [ -z "$NGROK_PUBLIC_URL" ]; then
    echo "Failed to get ngrok public URL. Exiting."
    exit 1
fi

echo "Ngrok Public URL: $NGROK_PUBLIC_URL"

# Run the Python bot, passing the ngrok URL as a command-line argument
python app.py "$NGROK_PUBLIC_URL"

# This script will exit when the python script exits, or when the GitHub Action times out.
# As GitHub Actions are not meant for persistent services, this job will eventually terminate.
