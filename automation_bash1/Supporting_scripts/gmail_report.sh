#!/bin/bash

# Check document VPS for the initial setup and mail server to connect to GMAIL
EMAIL="karisallan237@gmail.com"
MESSAGE="ALERT!!! CVE Critical!!"

echo -e "Subject: Critical Findings\n\n$MESSAGE" | msmtp "$EMAIL"
