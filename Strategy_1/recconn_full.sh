#!/usr/bin/env bash
# =============================================================================
#  BUG BOUNTY RECON AUTOMATION PIPELINE  (with AIx AI Analysis)
#  Tools: subfinder, assetfinder, httpx, subjack, waybackurls, gau, gf,
#         katana, hakrawler, unfurl, gowitness, nuclei, aix (gpt-5-nano)
#  AI:    aix (projectdiscovery) powered by OpenAI gpt-5-nano
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
TOKEN=""
CHAT_ID=""

AIX_MODEL="gpt-5-nano"             # model confirmed from screenshot
export OPENAI_API_KEY="KEY_HERE"   # set this in your shell or .bashrc

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

tg_msg() {
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$1" \
        -d parse_mode="HTML" > /dev/null
}

tg_file() {
    local filepath="$1" caption="${2:-File}"
    [[ -f "$filepath" && -s "$filepath" ]] || return 0
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendDocument" \
        -F chat_id="${CHAT_ID}" \
        -F document=@"${filepath}" \
        -F caption="${caption}" > /dev/null
}

# AI analysis via aix — pipes text to gpt-5-nano, returns analysis
# Usage: aix_analyze "system context" "data to analyze"
aix_analyze() {
    local context="$1"
    local data="$2"
    echo "$data" | aix -m "$AIX_MODEL" -sc "$context" -silent -nm 2>/dev/null || echo "[aix unavailable]"
}

# AI analyze a FILE and return insights
aix_analyze_file() {
    local context="$1"
    local file="$2"
    [[ -s "$file" ]] || { echo "[empty file — no analysis]"; return; }
    cat "$file" | aix -m "$AIX_MODEL" -sc "$context" -silent -nm 2>/dev/null || echo "[aix unavailable]"
}

log() { echo -e "\033[1;36m[*]\033[0m $1"; }
ok()  { echo -e "\033[1;32m[+]\033[0m $1"; }
warn(){ echo -e "\033[1;33m[!]\033[0m $1"; }
err() { echo -e "\033[1;31m[-]\033[0m $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# INPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

DOMAINS_FILE="${1:-domains.txt}"
OOS_FILE="out_of_scope.txt"

if [[ ! -f "$DOMAINS_FILE" ]]; then
    err "Usage: $0 <domains_file>   (default: domains.txt)"
    exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    warn "OPENAI_API_KEY not set — aix AI analysis will be skipped."
    warn "Export it with: export OPENAI_API_KEY=sk-..."
fi

START_TIME=$(date +%s)
DATE_TAG=$(date +"%Y-%m-%d_%H-%M")
GLOBAL_OUTPUT="recon_${DATE_TAG}"
mkdir -p "$GLOBAL_OUTPUT"

tg_msg "🚀 <b>Recon Pipeline Started</b>
📅 ${DATE_TAG}
📄 Scope: ${DOMAINS_FILE}  |  🎯 Domains: $(grep -vc '^\(#\|$\)' "$DOMAINS_FILE" || echo '?')
🤖 AI Model: ${AIX_MODEL} via aix
—————————————————————————"

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS EACH DOMAIN
# ─────────────────────────────────────────────────────────────────────────────

while IFS= read -r TARGET || [[ -n "$TARGET" ]]; do
    [[ -z "$TARGET" || "$TARGET" == \#* ]] && continue

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Target: $TARGET"

    DIR="${GLOBAL_OUTPUT}/${TARGET}"
    mkdir -p "${DIR}/urls" "${DIR}/screenshots" "${DIR}/nuclei" "${DIR}/secrets" "${DIR}/ai_reports"

    tg_msg "🎯 <b>Target: ${TARGET}</b>  |  ⏱ $(date +"%H:%M:%S")"

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 1 — SUBDOMAIN ENUMERATION
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "🔍 [${TARGET}] Phase 1: Subdomain Enumeration"

    log "Running subfinder..."
    subfinder -d "$TARGET" -silent 2>/dev/null | anew "${DIR}/subdomains.txt" || true

    log "Querying crt.sh..."
    curl -s "https://crt.sh/?q=%25.${TARGET}&output=json" \
        | jq -r '.[].name_value' 2>/dev/null \
        | sed 's/\*\.//g' | sort -u \
        | anew "${DIR}/subdomains.txt" || true

    log "Running assetfinder..."
    assetfinder --subs-only "$TARGET" 2>/dev/null \
        | sort -u | anew "${DIR}/subdomains.txt" || true

    # Strip out-of-scope
    if [[ -f "$OOS_FILE" ]]; then
        BEFORE=$(wc -l < "${DIR}/subdomains.txt")
        grep -vFf "$OOS_FILE" "${DIR}/subdomains.txt" > "${DIR}/subdomains_inscope.txt" || true
        mv "${DIR}/subdomains_inscope.txt" "${DIR}/subdomains.txt"
        warn "OOS filter: removed $((BEFORE - $(wc -l < "${DIR}/subdomains.txt"))) subdomains"
    fi
    sort -u "${DIR}/subdomains.txt" -o "${DIR}/subdomains.txt"

    # Interesting subdomains
    grep -Ei 'api|dev|stg|test|admin|demo|stag|pre|vpn|internal|beta|uat|backup|old|legacy|server|portal|dashboard|auth|login|sso|mail|smtp|ftp|remote' \
        "${DIR}/subdomains.txt" 2>/dev/null \
        | sort -u | tee "${DIR}/interesting_subdomains.txt" > /dev/null || true

    TOTAL_SUBS=$(wc -l < "${DIR}/subdomains.txt")
    INTERESTING=$(wc -l < "${DIR}/interesting_subdomains.txt")

    # ── AIx: Analyze interesting subdomains for attack surface ──────────────
    if [[ -s "${DIR}/interesting_subdomains.txt" ]]; then
        log "🤖 AIx: Analyzing interesting subdomains..."
        AI_SUB_REPORT=$(aix_analyze_file \
            "You are a bug bounty recon expert. Analyze these subdomains and identify: 1) Which look highest priority for testing, 2) Which patterns suggest admin panels, APIs, or staging servers, 3) Quick attack surface notes per subdomain. Be concise." \
            "${DIR}/interesting_subdomains.txt")
        echo "$AI_SUB_REPORT" > "${DIR}/ai_reports/subdomain_analysis.txt"
        tg_msg "🤖 <b>AIx Subdomain Analysis [${TARGET}]</b>

${AI_SUB_REPORT:0:3000}"
        tg_file "${DIR}/interesting_subdomains.txt" \
            "⚠️ [${TARGET}] Interesting subdomains (${INTERESTING})"
    fi

    tg_msg "📊 [${TARGET}] Subs: ${TOTAL_SUBS} total | ${INTERESTING} interesting"

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 2 — LIVE HOST DISCOVERY & TECH FINGERPRINTING
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "🌐 [${TARGET}] Phase 2: Live Hosts + Tech Fingerprint"

    cat "${DIR}/subdomains.txt" \
        | httpx -silent -o "${DIR}/live_hosts.txt" 2>/dev/null || true

    cat "${DIR}/live_hosts.txt" \
        | httpx -silent -title -tech-detect -status-code -content-length \
        -o "${DIR}/tech_fingerprint.txt" 2>/dev/null || true

    LIVE=$(wc -l < "${DIR}/live_hosts.txt")

    # ── AIx: Analyze tech stack for vuln ideas ──────────────────────────────
    if [[ -s "${DIR}/tech_fingerprint.txt" ]]; then
        log "🤖 AIx: Analyzing tech stack..."
        AI_TECH_REPORT=$(aix_analyze_file \
            "You are a bug bounty hunter. Given this httpx fingerprint output (url, title, technologies, status code, content-length), identify: 1) Technologies with known CVEs or misconfigs, 2) Interesting status codes (403, 401, 500), 3) Recommended nuclei template categories to run. Be concise and actionable." \
            "${DIR}/tech_fingerprint.txt")
        echo "$AI_TECH_REPORT" > "${DIR}/ai_reports/tech_analysis.txt"
        tg_msg "🤖 <b>AIx Tech Stack Analysis [${TARGET}]</b>

${AI_TECH_REPORT:0:3000}"
    fi

    tg_msg "✅ [${TARGET}] Live hosts: ${LIVE}"

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 3 — SUBDOMAIN TAKEOVER
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "🔀 [${TARGET}] Phase 3: Subdomain Takeover Check"

    subjack -w "${DIR}/subdomains.txt" \
        -ssl -t 100 -timeout 30 \
        -o "${DIR}/takeovers.txt" -v 2>/dev/null || true

    if [[ -s "${DIR}/takeovers.txt" ]]; then
        AI_TAKEOVER=$(aix_analyze_file \
            "You are a bug bounty expert. These are potential subdomain takeover findings from subjack. Explain the severity, which look exploitable, and write a one-paragraph CVSS-style impact statement for a bug report." \
            "${DIR}/takeovers.txt")
        echo "$AI_TAKEOVER" > "${DIR}/ai_reports/takeover_analysis.txt"
        tg_msg "🚨 <b>CRITICAL [${TARGET}]</b>: Subdomain takeover(s) detected!

🤖 AIx: ${AI_TAKEOVER:0:2000}"
        tg_file "${DIR}/takeovers.txt" "🚨 [${TARGET}] Subdomain Takeover — REVIEW NOW"
    else
        tg_msg "✅ [${TARGET}] No subdomain takeovers found."
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 4 — URL & PARAMETER DISCOVERY
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "🔗 [${TARGET}] Phase 4: URL + Parameter Discovery"

    echo "$TARGET" | waybackurls 2>/dev/null \
        | sort -u | anew "${DIR}/urls/wayback_urls.txt" || true

    gau "$TARGET" --threads 5 --subs 2>/dev/null \
        | sort -u | anew "${DIR}/urls/all_urls.txt" || true

    cat "${DIR}/urls/all_urls.txt" "${DIR}/urls/wayback_urls.txt" 2>/dev/null \
        | grep "?" | sort -u | uro 2>/dev/null \
        | anew "${DIR}/urls/params.txt" || true

    # GF pattern matching
    for pattern in xss sqli ssrf redirect lfi rce idor; do
        cat "${DIR}/urls/params.txt" \
            | gf "$pattern" 2>/dev/null \
            | anew "${DIR}/urls/${pattern}_params.txt" || true
    done

    cat "${DIR}/urls/xss_params.txt" "${DIR}/urls/sqli_params.txt" \
        "${DIR}/urls/ssrf_params.txt" "${DIR}/urls/redirect_params.txt" \
        "${DIR}/urls/lfi_params.txt" "${DIR}/urls/rce_params.txt" \
        "${DIR}/urls/idor_params.txt" 2>/dev/null \
        | sort -u > "${DIR}/urls/juicy_params.txt" || true

    PARAMS=$(wc -l < "${DIR}/urls/params.txt" 2>/dev/null || echo 0)
    JUICY=$(wc -l < "${DIR}/urls/juicy_params.txt" 2>/dev/null || echo 0)

    # ── AIx: Analyze juicy params for vuln prioritization ───────────────────
    if [[ -s "${DIR}/urls/juicy_params.txt" ]]; then
        log "🤖 AIx: Analyzing juicy parameters..."
        AI_PARAM_REPORT=$(aix_analyze_file \
            "You are a bug bounty hunter specializing in web vulnerabilities. Analyze these URLs with interesting parameters flagged by gf patterns (XSS, SQLi, SSRF, redirect, LFI, RCE, IDOR). Identify: 1) Top 5 highest-priority targets, 2) What payload to try first on each, 3) Any parameter names that suggest IDOR. Be concise and specific." \
            "${DIR}/urls/juicy_params.txt")
        echo "$AI_PARAM_REPORT" > "${DIR}/ai_reports/param_analysis.txt"
        tg_msg "🤖 <b>AIx Param Analysis [${TARGET}]</b>

${AI_PARAM_REPORT:0:3000}"
        tg_file "${DIR}/urls/juicy_params.txt" \
            "🎣 [${TARGET}] Juicy params — ${JUICY} GF matches"
    fi

    tg_msg "🔗 [${TARGET}] Params: ${PARAMS} total | ${JUICY} juicy GF matches"

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 5 — WEB CRAWLING (Katana + Hakrawler)
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "🕷️ [${TARGET}] Phase 5: Web Crawling (Katana + Hakrawler)..."

    cat "${DIR}/live_hosts.txt" \
        | katana -js-crawl -d 3 -silent 2>/dev/null \
        | grep "\.js$" | sort -u \
        | anew "${DIR}/secrets/js_files.txt" || true

    cat "${DIR}/urls/params.txt" \
        | katana 2>/dev/null \
        | hakrawler -d 3 2>/dev/null \
        | anew "${DIR}/urls/katana_crawl.txt" || true

    cat "${DIR}/urls/katana_crawl.txt" "${DIR}/urls/params.txt" 2>/dev/null \
        | unfurl format %p 2>/dev/null | sort -u \
        | anew "${DIR}/urls/new_paths.txt" || true

    cat "${DIR}/urls/katana_crawl.txt" "${DIR}/urls/params.txt" 2>/dev/null \
        | unfurl format %d 2>/dev/null | sort -u \
        | anew "${DIR}/subdomains.txt" || true

    sort -u "${DIR}/secrets/js_files.txt" "${DIR}/urls/new_paths.txt" 2>/dev/null \
        > "${DIR}/secrets/find_secrets_here.txt" || true

    JS_FILES=$(wc -l < "${DIR}/secrets/js_files.txt" 2>/dev/null || echo 0)
    NEW_PATHS=$(wc -l < "${DIR}/urls/new_paths.txt" 2>/dev/null || echo 0)

    # ── AIx: Analyze new paths for hidden endpoints ──────────────────────────
    if [[ -s "${DIR}/urls/new_paths.txt" ]]; then
        log "🤖 AIx: Analyzing crawled paths..."
        AI_PATH_REPORT=$(aix_analyze_file \
            "You are a bug bounty recon expert. Analyze these URL paths discovered by Katana/Hakrawler. Identify: 1) Paths that could be admin panels or sensitive endpoints, 2) Paths suggesting file upload, debug, or internal functionality, 3) Any patterns worth fuzzing with ffuf/feroxbuster. Be concise." \
            "${DIR}/urls/new_paths.txt")
        echo "$AI_PATH_REPORT" > "${DIR}/ai_reports/crawl_path_analysis.txt"
        tg_msg "🤖 <b>AIx Crawl Path Analysis [${TARGET}]</b>

${AI_PATH_REPORT:0:3000}"
    fi

    if [[ -s "${DIR}/secrets/find_secrets_here.txt" ]]; then
        tg_file "${DIR}/secrets/find_secrets_here.txt" \
            "🔑 [${TARGET}] JS + paths for SecretFinder — ${JS_FILES} JS, ${NEW_PATHS} paths"
    fi

    tg_msg "🕷️ [${TARGET}] Crawl done: ${JS_FILES} JS files | ${NEW_PATHS} new paths"

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 6 — EXPOSED SENSITIVE FILES
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "📂 [${TARGET}] Phase 6: Exposed Sensitive File Check"

    cat "${DIR}/live_hosts.txt" \
        | httpx -path "/.git/config" -mc 200 \
        -o "${DIR}/secrets/git_exposed.txt" 2>/dev/null || true

    cat "${DIR}/live_hosts.txt" \
        | httpx -path "/.env" -mc 200 \
        -o "${DIR}/secrets/env_files.txt" 2>/dev/null || true

    for path in "/.DS_Store" "/backup.zip" "/backup.tar.gz" "/db.sql" \
                "/config.php.bak" "/wp-config.php.bak" "/.htpasswd" \
                "/phpinfo.php" "/.well-known/security.txt"; do
        cat "${DIR}/live_hosts.txt" \
            | httpx -path "$path" -mc 200 \
            >> "${DIR}/secrets/extra_exposed.txt" 2>/dev/null || true
    done

    # JS secret grep
    cat "${DIR}/urls/all_urls.txt" 2>/dev/null \
        | grep "\.js$" | httpx -silent 2>/dev/null \
        | xargs -I % sh -c \
        'echo % && curl -s % | grep -Eo "(api|key|token|secret|password|apikey|api_key|access_token|auth)=[\"'"'"'][^\"'"'"']+[\"'"'"']"' \
        2>/dev/null >> "${DIR}/secrets/js_secrets_raw.txt" || true

    GIT_EXP=$(wc -l < "${DIR}/secrets/git_exposed.txt" 2>/dev/null || echo 0)
    ENV_EXP=$(wc -l < "${DIR}/secrets/env_files.txt" 2>/dev/null || echo 0)

    if [[ "$GIT_EXP" -gt 0 ]]; then
        AI_GIT=$(aix_analyze \
            "You are a bug bounty expert. A .git/config file is publicly accessible." \
            "$(cat "${DIR}/secrets/git_exposed.txt") — explain severity, impact, and how to exploit for a bug report.")
        tg_msg "🚨 <b>CRITICAL [${TARGET}]</b>: ${GIT_EXP} exposed .git/config!
🤖 AIx: ${AI_GIT:0:1500}"
        tg_file "${DIR}/secrets/git_exposed.txt" "🚨 [${TARGET}] .git/config exposed — CRITICAL"
    fi

    if [[ "$ENV_EXP" -gt 0 ]]; then
        AI_ENV=$(aix_analyze \
            "You are a bug bounty expert. An .env file is publicly accessible." \
            "$(cat "${DIR}/secrets/env_files.txt") — explain severity, impact, and what to look for inside for a bug report.")
        tg_msg "🚨 <b>CRITICAL [${TARGET}]</b>: ${ENV_EXP} exposed .env files!
🤖 AIx: ${AI_ENV:0:1500}"
        tg_file "${DIR}/secrets/env_files.txt" "🚨 [${TARGET}] .env exposed — CRITICAL"
    fi

    if [[ -s "${DIR}/secrets/js_secrets_raw.txt" ]]; then
        AI_JS=$(aix_analyze_file \
            "You are a security researcher. These are potential secrets found in JavaScript files via regex grep. Identify which look like real API keys, tokens, or credentials vs false positives. Prioritize by risk." \
            "${DIR}/secrets/js_secrets_raw.txt")
        echo "$AI_JS" > "${DIR}/ai_reports/js_secrets_analysis.txt"
        tg_msg "🔑 <b>AIx JS Secrets [${TARGET}]</b>:
${AI_JS:0:2000}"
        tg_file "${DIR}/secrets/js_secrets_raw.txt" "🔑 [${TARGET}] JS secrets (raw)"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 7 — SCREENSHOTS (gowitness → zipped)
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "📸 [${TARGET}] Phase 7: Screenshots (gowitness)"

    gowitness scan file \
        -f "${DIR}/live_hosts.txt" \
        --screenshot-path "${DIR}/screenshots/" \
        --disable-db 2>/dev/null || true

    SCREENSHOT_COUNT=$(find "${DIR}/screenshots/" -name "*.png" 2>/dev/null | wc -l)

    if [[ "$SCREENSHOT_COUNT" -gt 0 ]]; then
        SCRNZIP="${DIR}/screenshots_${TARGET}.zip"
        zip -rj "$SCRNZIP" "${DIR}/screenshots/" >/dev/null 2>&1 || true
        tg_file "$SCRNZIP" "📸 [${TARGET}] ${SCREENSHOT_COUNT} screenshots"
    else
        tg_msg "📸 [${TARGET}] No screenshots captured."
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 8 — NUCLEI SCANNING  (slowest — runs last)
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "☢️ [${TARGET}] Phase 8: Nuclei Scan (critical/high/medium)..."

    subfinder -d "$TARGET" -silent 2>/dev/null \
        | httpx -silent -title -tech-detect -status-code 2>/dev/null \
        | tee "${DIR}/nuclei/live_tech.txt" \
        | awk '{print $1}' \
        | nuclei \
            -t ~/nuclei-templates/ \
            -severity critical,high,medium \
            -silent \
            -o "${DIR}/nuclei/vuln_report.txt" 2>/dev/null || true

    nuclei \
        -l "${DIR}/live_hosts.txt" \
        -t ~/nuclei-templates/sql-injection/ \
        -severity critical \
        -o "${DIR}/nuclei/nuclei_sqli.txt" 2>/dev/null || true

    cat "${DIR}/nuclei/vuln_report.txt" \
        "${DIR}/nuclei/nuclei_sqli.txt" 2>/dev/null \
        | sort -u > "${DIR}/nuclei/all_vulns.txt" || true

    VULN_COUNT=$(wc -l < "${DIR}/nuclei/all_vulns.txt" 2>/dev/null || echo 0)

    # ── AIx: Analyze nuclei findings & draft bug report ─────────────────────
    if [[ "$VULN_COUNT" -gt 0 ]]; then
        log "🤖 AIx: Analyzing Nuclei findings and drafting bug report..."
        AI_VULN_REPORT=$(aix_analyze_file \
            "You are an expert bug bounty hunter writing a vulnerability report. Given these Nuclei findings: 1) Rank by severity and exploitability, 2) For the top 3 findings write a one-paragraph description suitable for a HackerOne/Bugcrowd report including: vulnerability name, affected URL, impact, CVSS estimate, and recommended fix. Be specific and professional." \
            "${DIR}/nuclei/all_vulns.txt")
        echo "$AI_VULN_REPORT" > "${DIR}/ai_reports/nuclei_vuln_analysis.txt"
        tg_msg "🚨 <b>Nuclei Findings [${TARGET}]</b>: ${VULN_COUNT} issues!

🤖 <b>AIx Bug Report Draft:</b>
${AI_VULN_REPORT:0:3500}"
        tg_file "${DIR}/nuclei/all_vulns.txt" \
            "🚨 [${TARGET}] Nuclei — ${VULN_COUNT} vulns (critical/high/medium)"
        tg_file "${DIR}/ai_reports/nuclei_vuln_analysis.txt" \
            "📝 [${TARGET}] AIx Bug Report Draft — ready to polish!"
    else
        tg_msg "✅ [${TARGET}] Nuclei: No critical/high/medium findings."
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # PHASE 9 — AIx FULL DOMAIN ATTACK SURFACE SUMMARY
    # ─────────────────────────────────────────────────────────────────────────

    log "🤖 AIx: Generating full attack surface summary for ${TARGET}..."

    SUMMARY_DATA="Target: ${TARGET}
Total subdomains: ${TOTAL_SUBS}
Interesting subdomains: ${INTERESTING}
Live hosts: ${LIVE}
Total param URLs: ${PARAMS}
Juicy GF params: ${JUICY}
JS files found: ${JS_FILES}
New crawled paths: ${NEW_PATHS}
Exposed .git: ${GIT_EXP}
Exposed .env: ${ENV_EXP}
Screenshots: ${SCREENSHOT_COUNT}
Nuclei findings: ${VULN_COUNT}
Tech fingerprint summary:
$(head -30 "${DIR}/tech_fingerprint.txt" 2>/dev/null || echo 'N/A')"

    AI_FULL_SUMMARY=$(aix_analyze \
        "You are a senior bug bounty hunter. Given this recon summary for a target, write a strategic attack plan: 1) Top 3 areas to focus on, 2) Most likely vulnerability classes based on the tech stack, 3) Recommended next manual steps. Keep it actionable and under 400 words." \
        "$SUMMARY_DATA")
    echo "$AI_FULL_SUMMARY" > "${DIR}/ai_reports/full_attack_plan.txt"

    tg_msg "🗺️ <b>AIx Attack Plan [${TARGET}]</b>

${AI_FULL_SUMMARY:0:3500}"
    tg_file "${DIR}/ai_reports/full_attack_plan.txt" \
        "🗺️ [${TARGET}] AIx Full Attack Plan — strategic next steps"

    # ─────────────────────────────────────────────────────────────────────────
    # DOMAIN SUMMARY
    # ─────────────────────────────────────────────────────────────────────────

    tg_msg "✅ <b>Complete: ${TARGET}</b>
━━━━━━━━━━━━━━━━━━━
📌 Subdomains:   ${TOTAL_SUBS}
⭐ Interesting:  ${INTERESTING}
🌐 Live hosts:   ${LIVE}
🔗 Param URLs:   ${PARAMS}
🎣 Juicy params: ${JUICY}
🕷️ JS files:     ${JS_FILES}
📸 Screenshots:  ${SCREENSHOT_COUNT}
☢️ Nuclei vulns: ${VULN_COUNT}
🤖 AI Reports:   $(ls "${DIR}/ai_reports/" | wc -l) generated
━━━━━━━━━━━━━━━━━━━"

done < "$DOMAINS_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
HOURS=$(( ELAPSED / 3600 ))
MINS=$(( (ELAPSED % 3600) / 60 ))
SECS=$(( ELAPSED % 60 ))

tg_msg "🏁 <b>Pipeline Complete</b>
⏱ Runtime: ${HOURS}h ${MINS}m ${SECS}s
📁 Results: ${GLOBAL_OUTPUT}/
🤖 AI model used: ${AIX_MODEL}

<i>Happy hunting! 🐛💰</i>"

ok "Done! Results: ${GLOBAL_OUTPUT}/"
echo "[*] Runtime: ${HOURS}h ${MINS}m ${SECS}s"