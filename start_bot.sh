#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting ngrok in background..."
# Start ngrok, redirecting stdout and stderr to a log file.
# Using 'exec' to replace the current shell with ngrok, ensuring proper process management.
# However, since we want to capture PID and run other commands, keep it as background process.
./ngrok http 8000 > ngrok.log 2>&1 &

# Store the Process ID of ngrok
NGROK_PID=$!
echo "Ngrok started with PID: $NGROK_PID"

# Wait for ngrok to start and for its local API to be available
echo "Waiting for ngrok to start and expose its API..."
NGROK_API_URL="http://localhost:4040/api/tunnels"
MAX_RETRIES=30 # Increased retries significantly
RETRY_DELAY=5 # Increased delay to give ngrok more time

for i in $(seq 1 $MAX_RETRIES); do
    # Check if ngrok process is still running
    if ! ps -p $NGROK_PID > /dev/null; then
        echo "Ngrok process died unexpectedly."
        echo "Dumping ngrok.log for details:"
        cat ngrok.log # Print ngrok's log for debugging
        exit 1
    fi

    # Attempt to curl the ngrok API
    # Store the full response for debugging
    NGROK_API_RESPONSE=$(curl -s "$NGROK_API_URL")
    HTTP_STATUS=$(echo "$NGROK_API_RESPONSE" | head -n 1 | grep -oP 'HTTP/\d\.\d \K\d{3}') # Extract HTTP status if present

    if [ -z "$HTTP_STATUS" ]; then
        # If no HTTP status, it means curl likely failed to connect or the response was empty/malformed.
        echo "Ngrok API not yet available or returned an empty/malformed response (Attempt $i/$MAX_RETRIES)."
        echo "Full API response (if any):"
        echo "$NGROK_API_RESPONSE"
        sleep $RETRY_DELAY
    elif [ "$HTTP_STATUS" -eq 200 ]; then
        echo "Ngrok API is available (HTTP 200 OK)."
        # Check if the response contains 'tunnels' array and it's not empty
        if echo "$NGROK_API_RESPONSE" | jq -e '.tunnels | length > 0' > /dev/null; then
            echo "Ngrok API response contains active tunnels."
            break # Exit loop if API is ready and tunnels exist
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
        cat ngrok.log # Print ngrok's log before exiting
        exit 1
    fi
done

# Get the ngrok public URL
# Use 'jq -r' to get raw string output and handle potential nulls gracefully
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

# Export TELEGRAM_BOT_TOKEN so app.py can access it
# Ensure this secret is correctly configured in GitHub Actions
export TELEGRAM_BOT_TOKEN="${{ secrets.TELEGRAM_BOT_TOKEN }}"

# Run the Python bot, passing the ngrok URL as a command-line argument
# Use 'exec' to replace the current shell with the python process,
# which can help with signal handling and ensures the script exits when python exits.
exec python app.py "$NGROK_PUBLIC_URL"

# This script will exit when the python script exits, or when the GitHub Action times out.
# As GitHub Actions are not meant for persistent services, this job will eventually terminate.
