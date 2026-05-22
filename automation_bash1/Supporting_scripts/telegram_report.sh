#!/bin/bash

# Configuration
TOKEN="BOT_TOKEN_HERE"
CHAT_ID="CHAT_ID_HERE"
MESSAGE="Server backup completed successfully! ✅"

# Send message
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d chat_id="$CHAT_ID" \
     -d text="$MESSAGE" \
     -d parse_mode="HTML" > /dev/null
