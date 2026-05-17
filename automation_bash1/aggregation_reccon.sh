#!/bin/bash

# Get the first argument as input and store in variable (NO spaces around =)
domain=$1

# Check if domain is provided
if [ -z "$domain" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

echo "[+] Starting subdomain enumeration for: $domain"

# Create temp files to avoid conflicts
> all_subs.txt
> amass.txt

# Run multiple tools in parallel
subfinder -d "$domain" -silent | tee -a all_subs.txt &
amass enum -passive -d "$domain" -o amass.txt &
assetfinder --subs-only "$domain" | tee -a all_subs.txt &

# Wait for all to complete
wait

# Merge and deduplicate
cat all_subs.txt amass.txt 2>/dev/null | sort -u > unique_subs.txt

# Check if we found any subdomains
sub_count=$(wc -l < unique_subs.txt)
echo "[+] Found $sub_count unique subdomains"

# Generate subdomain permutations (only if we have subdomains)
if [ -s unique_subs.txt ]; then
    echo "[+] Generating permutations and resolving..."
    cat unique_subs.txt | dnsgen - | massdns -r resolver.txt -t A -o J --flush -w massdns_out.json 2>/dev/null
    echo "[+] Results saved to massdns_out.json"
else
    echo "[-] No subdomains found to permutate"
fi