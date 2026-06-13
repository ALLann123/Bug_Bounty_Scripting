#!/usr/bin/env bash

# set the target
TARGET="naivas.online"

echo "[+]STarting Recon"
# Triggerr subfinder save results to txt file
echo "[+] Running Subdfinder...."
subfinder -d $TARGET -silent | anew subdomains.txt

#crt.sh query to get any https subdomains of the domain issued to serve https
echo "[+] Running crt.sh query using curl...."
curl -s "https://crt.sh/?q=%25.$TARGET&output=json" | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u | anew subdomains.txt

# assetfinder adds additional subdomains
#sort -u = sort + unique---> removes duplicate lines
echo "[+] Running Assetfinder....."
assetfinder --subs-only $TARGET | sort -u | anew subdomains.txt

#clean up entire file just incase
sort -u subdomains.txt -o subdomains.txt

echo "[+] Filtering interesting subdomains....."
# Lets filter interesting ones from the list
#		1. API Endpoints
#		2. Developer environments
#		3. Staging servers and admin panels
#		4. VPNs and internal tools
grep -Ei 'api|dev|stg|test|admin|demo|stag*|pre|vpn|internal|beta|uat|backup|old|legacy|server' subdomains.txt \
| sort -u \
| tee interesting_subdomains.txt
# Remember misconfigured=critical finding
# tee displays output AND saves it

echo -e "\n"
echo "[*] Total Subdomains: $(wc -l < subdomains.txt)"
echo "[*] Interesting subdomains: $(wc -l < interesting_subdomains.txt)"
