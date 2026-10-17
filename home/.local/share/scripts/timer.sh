#!/bin/bash

### Cycling Stopwatch for Polybar - F9 Key Toggle
### States: hidden -> running -> stopped -> hidden
### Fixed for initial hidden state, reliable cycling, and immediate updates

## FUNCTIONS

now() { date --utc +%s; }

killTimer() { rm -rf /tmp/polybar-cycle-timer; }
timerExists() { [ -e /tmp/polybar-cycle-timer ]; }
timerState() {
  if ! timerExists; then
    echo "hidden"
  else
    [ -f /tmp/polybar-cycle-timer/state ] && cat /tmp/polybar-cycle-timer/state || echo "hidden"
  fi
}

timerStart() {
  if [ -f /tmp/polybar-cycle-timer/start ]; then
    cat /tmp/polybar-cycle-timer/start
  else
    echo "0"
  fi
}
secondsElapsed() {
  local start=$(timerStart)
  if [ "$start" -eq 0 ]; then
    echo 0
  else
    echo $(($(now) - start))
  fi
}
formatTime() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local secs=$((seconds % 60))
  printf "%02d:%02d" "$minutes" "$secs"
}

updateTail() {
  local state=$(timerState)

  # For debugging: uncomment to log state changes
  # echo "$(date): State: $state" >> /tmp/polybar-timer-debug.log

  case "$state" in
  "hidden")
    printf "\n" # Explicit newline for proper hiding
    ;;
  "running")
    local elapsed=$(secondsElapsed)
    printf "⏱ %s\n" "$(formatTime $elapsed)"
    ;;
  "stopped")
    local elapsed=0
    if [ -f /tmp/polybar-cycle-timer/paused_time ]; then
      elapsed=$(cat /tmp/polybar-cycle-timer/paused_time)
    fi
    printf "⏱ %s ⏸\n" "$(formatTime $elapsed)"
    ;;
  esac
}

toggleTimer() {
  local current_state=$(timerState)

  # For debugging: uncomment to log toggles
  # echo "$(date): Toggling from $current_state" >> /tmp/polybar-timer-debug.log

  case "$current_state" in
  "hidden")
    # Show and start running from 00:00
    mkdir -p /tmp/polybar-cycle-timer
    echo "running" >/tmp/polybar-cycle-timer/state
    echo "$(now)" >/tmp/polybar-cycle-timer/start
    rm -f /tmp/polybar-cycle-timer/paused_time
    ;;
  "running")
    # Stop (pause) but keep visible
    if timerExists; then
      local elapsed=$(secondsElapsed)
      echo "stopped" >/tmp/polybar-cycle-timer/state
      echo "$elapsed" >/tmp/polybar-cycle-timer/paused_time
      rm -f /tmp/polybar-cycle-timer/start
    fi
    ;;
  "stopped")
    # Hide and reset
    killTimer
    ;;
  esac

  # Force Polybar update via hook (if running in Polybar context)
  polybar-msg hook cycle-timer 1 2>/dev/null
}

## MAIN CODE

case $1 in
tail)
  trap 'updateTail' USR1

  while true; do
    updateTail
    sleep ${2:-1} &
    wait
  done
  ;;
toggle)
  toggleTimer
  ;;
*)
  echo "Usage: $0 {tail|toggle}"
  ;;
esac
