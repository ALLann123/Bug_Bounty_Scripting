#!/bin/bash
# Bug Bounty Automation Pipeline
# Usage: ./recon.sh example.com
domain=$1
output_dir="recon_${domain}_$(date +%Y%m%d)"
mkdir -p $output_dir
echo "[*] Starting reconnaissance for $domain"
# Step 1: Subdomain Enumeration
echo "[*] Phase 1: Subdomain Discovery"
subfinder -d $domain -all -silent -o $output_dir/subfinder.txt &
amass enum -passive -d $domain -o $output_dir/amass.txt &
assetfinder --subs-only $domain > $output_dir/assetfinder.txt &
wait
# Merge and deduplicate
cat $output_dir/subfinder.txt $output_dir/amass.txt $output_dir/assetfinder.txt | sort -u > $output_dir/all_subdomains.txt
echo "[+] Found $(wc -l < $output_dir/all_subdomains.txt) unique subdomains"
# Step 2: Subdomain Permutation
echo "[*] Phase 2: Generating permutations"
cat $output_dir/all_subdomains.txt | dnsgen - | massdns -r resolvers.txt -t A -o J --flush 2>/dev/null | grep -oP '(?<=")[^"]+(?=")' | sort -u > $output_dir/resolved_subs.txt
echo "[+] Resolved $(wc -l < $output_dir/resolved_subs.txt) ...erability scanning"
nuclei -l $output_dir/all_urls.txt -severity critical,high -o $output_dir/nuclei_findings.txt -silent
# Check if any critical/high findings
if [ -s $output_dir/nuclei_findings.txt ]; then
    echo "[!] CRITICAL/HIGH vulnerabilities found!"
    # Send notification
    python3 notify.py --file $output_dir/nuclei_findings.txt --domain $domain
else
    echo "[*] No critical/high vulnerabilities found"
fi
# Step 6: Generate report
echo "[*] Generating summary report"
echo "=== Reconnaissance Report for $domain ===" > $output_dir/report.txt
echo "Date: $(date)" >> $output_dir/report.txt
echo "Subdomains: $(wc -l < $output_dir/all_subdomains.txt)" >> $output_dir/report.txt
echo "Live Hosts: $(wc -l < $output_dir/live_hosts.txt)" >> $output_dir/report.txt
echo "URLs: $(wc -l < $output_dir/all_urls.txt)" >> $output_dir/report.txt
echo "Findings: $(wc -l < $output_dir/nuclei_findings.txt)" >> $output_dir/report.txt
echo "[+] Reconnaissance complete! Results in $output_dir/"