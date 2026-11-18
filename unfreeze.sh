#!/system/bin/sh
# unfreeze.sh — resume all T-state (signal-stopped) processes
count=0
ps -A -o PID,S,NAME 2>/dev/null | while read pid st name; do
    if [ "$st" = "T" ] || [ "$st" = "t" ]; then
        kill -18 "$pid" 2>/dev/null && count=$((count+1)) && echo "CONT $pid $name"
    fi
done
echo "=== remaining stopped: $(ps -A -o PID,S,NAME 2>/dev/null | grep -cE ' [Tt] ') ==="
