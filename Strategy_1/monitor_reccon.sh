#!/usr/bin/env bash
# =============================================================================
#  RECON PIPELINE MONITOR
#  Usage: ./monitor.sh <PID>
#  Checks the target PID every 30 minutes and reports status to Telegram.
# =============================================================================

# ─── Telegram Config ──────────────────────────────────────────────────────────
TOKEN=""
CHAT_ID=""

# ─── Input Validation ─────────────────────────────────────────────────────────
getPIDTARGET=$1

if [[ -z "$getPIDTARGET" ]]; then
    echo "Usage: $0 <PID>"
    echo "Example: $0 12345"
    exit 1
fi

if ! [[ "$getPIDTARGET" =~ ^[0-9]+$ ]]; then
    echo "[-] Error: PID must be a number."
    exit 1
fi

# ─── Helper Functions ─────────────────────────────────────────────────────────

tg_msg() {
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$1" \
        -d parse_mode="HTML" > /dev/null
}

format_elapsed() {
    local secs=$1
    local h=$(( secs / 3600 ))
    local m=$(( (secs % 3600) / 60 ))
    local s=$(( secs % 60 ))
    printf "%dh %02dm %02ds" "$h" "$m" "$s"
}

get_proc_info() {
    # Returns command name + cpu + mem usage for the PID
    ps -p "$getPIDTARGET" -o comm=,pcpu=,pmem=,etime= 2>/dev/null | head -1 || echo "N/A"
}

# ─── Init ─────────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)
START_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")
CHECK_INTERVAL=180           #1800   # 30 minutes in seconds
CHECK_COUNT=0

# Confirm the PID actually exists before we start
if ! kill -0 "$getPIDTARGET" 2>/dev/null; then
    echo "[-] PID $getPIDTARGET does not exist or is not accessible."
    tg_msg "❌ <b>Monitor Error</b>
PID <code>${getPIDTARGET}</code> was not found.
It may have already finished or the PID is wrong.
⏰ Checked at: ${START_HUMAN}"
    exit 1
fi

PROC_NAME=$(ps -p "$getPIDTARGET" -o comm= 2>/dev/null || echo "unknown")

echo "[+] Starting monitoring of PID: $getPIDTARGET ($PROC_NAME)"
echo "[+] Check interval: every 30 minutes"
echo "[+] Started at: $START_HUMAN"

tg_msg "👁️ <b>Recon Monitor Started</b>
━━━━━━━━━━━━━━━━━━━
🔢 PID:      <code>${getPIDTARGET}</code>
⚙️  Process:  <code>${PROC_NAME}</code>
🕐 Started:  ${START_HUMAN}
🔁 Interval: every 30 minutes
━━━━━━━━━━━━━━━━━━━
<i>Will alert you when it finishes or every 30 mins while running.</i>"

# ─── Monitor Loop ─────────────────────────────────────────────────────────────

while true; do
    sleep "$CHECK_INTERVAL"

    NOW=$(date +%s)
    NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")
    ELAPSED=$(( NOW - START_TIME ))
    ELAPSED_FMT=$(format_elapsed "$ELAPSED")
    CHECK_COUNT=$(( CHECK_COUNT + 1 ))

    if kill -0 "$getPIDTARGET" 2>/dev/null; then
        # ── Process is STILL RUNNING ─────────────────────────────────────────
        PROC_INFO=$(get_proc_info)
        CPU=$(echo "$PROC_INFO" | awk '{print $2}')
        MEM=$(echo "$PROC_INFO" | awk '{print $3}')
        ETIME=$(echo "$PROC_INFO" | awk '{print $4}')

        echo "[+] [$NOW_HUMAN] PID $getPIDTARGET still running | Elapsed: $ELAPSED_FMT | Check #$CHECK_COUNT"

        tg_msg "✅ <b>Recon Still Running</b>  [Check #${CHECK_COUNT}]
━━━━━━━━━━━━━━━━━━━
🔢 PID:        <code>${getPIDTARGET}</code>
⚙️  Process:    <code>${PROC_NAME}</code>
⏱ Monitored:  ${ELAPSED_FMT}
🕰 Proc uptime: ${ETIME}
📊 CPU usage:  ${CPU}%
💾 Mem usage:  ${MEM}%
🕐 Time now:   ${NOW_HUMAN}
━━━━━━━━━━━━━━━━━━━
<i>Next check in 30 minutes...</i>"

    else
        # ── Process has FINISHED ─────────────────────────────────────────────
        END_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")
        TOTAL_ELAPSED=$(format_elapsed "$ELAPSED")

        echo "[!] [$END_HUMAN] PID $getPIDTARGET is NO LONGER running."
        echo "[*] Total monitored time: $TOTAL_ELAPSED"
        echo "[*] Total checks made: $CHECK_COUNT"

        tg_msg "🏁 <b>Recon Pipeline Finished!</b>
━━━━━━━━━━━━━━━━━━━
🔢 PID:           <code>${getPIDTARGET}</code>
⚙️  Process:       <code>${PROC_NAME}</code>
✅ Status:         Completed / Stopped
⏱ Total runtime: ${TOTAL_ELAPSED}
🔁 Total checks:  ${CHECK_COUNT}
🕐 Ended at:      ${END_HUMAN}
━━━━━━━━━━━━━━━━━━━
<i>Go check your results! 🐛💰</i>"

        exit 0
    fi
done