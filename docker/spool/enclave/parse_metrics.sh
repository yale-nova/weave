#!/bin/bash

LOG="worker_metrics.log"

echo "📊 Max Memory Stats (in MB)"
grep 'Vm' "$LOG" | awk '{a[$1] = ($2 > a[$1] ? $2 : a[$1])} END {for (k in a) printf "%s %.2f MB\n", k, a[k]/1024}' | sort

echo -e "\n🧵 Max Thread Count:"
awk '/\[Threads\]/ {getline; match($0, /[0-9]+/, m); if (m[0] != "") print m[0]}' "$LOG" | sort -nr | head -1

echo -e "\n📏 Max Stack Size Used by Any Thread:"
grep 'stack size' "$LOG" | awk '{print $(NF-1)}' | sort -nr | head -1

echo -e "\n📂 Max Open File Descriptors:"
grep 'Open FDs:' "$LOG" | awk '{print $NF}' | sort -nr | head -1

echo -e "\n🔢 Max System Open FDs Limit:"
grep 'Max open files' "$LOG" | awk '{print $4}' | sort -nr | head -1

echo -e "\n🔢 Max System Stack Limit:"
grep 'Max stack size' "$LOG" | awk '{print $(NF-1)}' | sort -nr | head -1