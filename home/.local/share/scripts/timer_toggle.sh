#!/bin/bash

STATE_FILE="/tmp/polybar_timer_state"
TIME_FILE="/tmp/polybar_timer_time"
START_FILE="/tmp/polybar_timer_start"

# Initialize state file if it doesn't exist
[ ! -f "$STATE_FILE" ] && echo "hidden" >"$STATE_FILE"

CURRENT_STATE=$(cat "$STATE_FILE")

case "$CURRENT_STATE" in
"hidden")
  # Show and start timer
  echo "running" >"$STATE_FILE"
  echo "0" >"$TIME_FILE"
  date +%s >"$START_FILE"
  ;;
"running")
  # Stop timer but keep visible
  echo "stopped" >"$STATE_FILE"
  rm -f "$START_FILE"
  ;;
"stopped")
  # Hide timer
  echo "hidden" >"$STATE_FILE"
  rm -f "$TIME_FILE" "$START_FILE"
  ;;
esac
