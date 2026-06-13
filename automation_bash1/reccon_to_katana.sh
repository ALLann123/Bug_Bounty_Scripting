#!/usr/bin/env bash

# Telegram Variables
# ********Telegram Variables*********************
# configurations
TOKEN=""
CHAT_ID=""
#************************************************

# set the target
# get the first argument as input
TARGET=$1

# Now we exit if the script has no argument
if [ -z "$1" ]
then
	echo "Usage: $0 <target_domain>"
	exit 1
fi

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

echo -e "\n[+] Filtering interesting subdomains....."
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
FILTERED_SUBS="interesting_subdomains.txt"
# send these to alert hunters on Telegram
# Send compressed file
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
     -F chat_id="$CHAT_ID" \
     -F document=@"$FILTERED_SUBS" \
     -F caption="Interesting subdomains in $1🔥🔥" > /dev/null

# Check Live Subdomains with httpx
echo -e "\n[+]Discovering Live Subdomains using httpx...."
# filter dead subdomains
cat subdomains.txt | httpx -silent -o live_hosts.txt

# Fingerprinting, techstack
echo "[+] Discovering technologies in the live subdomains...."
# Know what you're attacking
cat live_hosts.txt | httpx -silent -title -tech-detect -status-code -content-length
# We get Page title, technologies, HTTP Status code, content length

# Try subdomain Take Over with sujack scanner
echo -e "\n[+] Attempting subdomain takeover with subjack..."
# check every subdomain for signs of subdomain takeover
subjack -w subdomains.txt -ssl -t 100 -timeout 30 -o takeovers.txt -v

# Screenshots + ALert delivery to Telegram(Make sure to check if file is empty first)
# 1. Trigger screenshot taking
# 2. Check if folder is empty
# 3. if not empty, compress the target folder and call the telegram 
# bot API to send an alert with the file

echo -e "\n[+]Aquatone attempting screenshots on live subdomains...."
# run aquatone
cat live_hosts.txt | aquatone -out screenshots/

# our target folder is ut
TARGET_DIR="ut"

# check folder is not empty then send to Telegram
if [ "$(ls -A "$TARGET_DIR")" ]
then
	echo "[+] Folder contains files"

	#compress folder
	tar -czf view_subs.tar.gz $TARGET_DIR

	echo "[+] Archive created, time to send...."

	# our file archieve
	FILE="view_subs.tar.gz"

	# Send compressed file
	curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
	     -F chat_id="$CHAT_ID" \
	     -F document=@"$FILE" \
	     -F caption="View Screenshot of subdomains of $1" > /dev/null

	echo "[+] Screenshot file alert send!!"

else
	echo "[-] Folder is empty!!"
fi

echo -e "\n"
echo "[*] Total Subdomains: $(wc -l < subdomains.txt)"
echo "[*] Interesting subdomains: $(wc -l < interesting_subdomains.txt)"
echo "[*] live subdomains: $(wc -l < live_hosts.txt)"

echo -e "\n\n\n"

#************************************************
#	PHASE 2: Port Scanning and Service Discovery
#************************************************
# Wayback machine--> unforgotten endpoints
mkdir urls
echo $TARGET | waybackurls | sort -u | anew url/wayback_urls.txt

# GAU--> Query more sources of forgotten endpoints
gau $TARGET --threads 5 --subs | sort -u | anew url/all_urls.txt

# Extract Only parameters(XSS/SQLi Gold)--> combine the results
# 1. GAU results
cat url/all_urls.txt | grep "?" | sort -u | uro | anew url/params.txt

# 2. waybackurls
cat url/wayback_urls.txt | grep "?" | sort -u | uro | anew url/params.txt

# 3. GF---> discover parameter patterns with GF XSS, SQLI, SSRF, redirect
cat url/params.txt | gf xss | anew url/xss_params.txt
cat url/params.txt | gf sqli | anew url/sqli_params.txt
cat url/params.txt | gf ssrf | anew url/ssrf_params.txt
cat url/params.txt | gf redirect | anew url/redirect_params.txt


# When done with the above notify user
MESSAGE="[+] Starting Katana and Hakrawler, may take a while!!😭😭😭😭"

# Send message
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d chat_id="$CHAT_ID" \
     -d text="$MESSAGE" \
     -d parse_mode="HTML" > /dev/null

# 4. Katana Web Crawler + Hakrawler for additional findings(uses REGEX)
cat live_hosts.txt | katana -js-crawl -d 3 -silent | grep "\.js$" | sort -u | anew js_files.txt

# combined
cat url/params.txt | katana | hakrawler -d 3 | anew katana.txt
# new_paths
cat katana.txt url/params.txt | unfurl format %p | anew new_paths.txt
# new subdomains
cat katana.txt url/params.txt | unfurl format %d | anew more_subs.txt

# Now send a message
MESSAGE="🎉🎉Katana has completed!! Come run secretfinder.py in virtual environment, to find secrets. Also we have new_paths: $(wc -l new_paths.txt) and new_subs: $(wc -l new_paths.txt) to explore"

# Send message
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d chat_id="$CHAT_ID" \
     -d text="$MESSAGE" \
     -d parse_mode="HTML" > /dev/null

# Combine files for katana and hakrawler
sort -u js_files.txt new_paths.txt > find_secrets_here.txt

SECRET_JS="find_secrets_here.txt"

# Send compressed file
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
	-F chat_id="$CHAT_ID" \
	-F document=@"$SECRET_JS" \
	-F caption="Crawled js output may contain secrets!!🚨🚨Contains: $(wc -l find_secrets_here.txt)" > /dev/null
	

