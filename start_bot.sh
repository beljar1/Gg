#!/bin/bash

ngrok http 8000 --authtoken "$NGROK_AUTH_TOKEN" > /dev/null &

sleep 5

NGROK_PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')

if [ -z "$NGROK_PUBLIC_URL" ]; then
    echo "Failed to get ngrok public URL. Exiting."
    exit 1
fi

echo "Ngrok Public URL: $NGROK_PUBLIC_URL"

python app.py "$NGROK_PUBLIC_URL"
