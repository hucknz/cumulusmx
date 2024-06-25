#!/bin/bash

# Start nginx web server
service nginx start

# Copy Web Support Files
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Copy Public Web Templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/

# Handle container shutdown
pid=0

# SIGTERM handler copies files to config folder when container stops
term_handler() {
  if [ $pid -ne 0 ]; then
    kill -SIGTERM "$pid"
    wait "$pid"
    sleep 2
    if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
      cp -f /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/
    fi
    if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
      cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/
    fi
  fi
  exit 143; # 128 + 15 -- SIGTERM
}

# Setup handlers
trap 'kill ${!}; term_handler' SIGTERM

# Run application
if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
  cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
fi
mono /opt/CumulusMX/CumulusMX.exe >> /var/log/nginx/CumulusMX.log &
pid="$!"

# Get the latest log file
get_latest_logfile() {
  ls -1 /opt/CumulusMX/MXdiags | grep -E '^[0-9]{8}-[0-9]{6}\.txt$' | sort | tail -n 1
}

# Initialize the latest log file variable
latest_logfile=""

# Continuously check for new log files and tail the latest one
(
  while true; do
    current_logfile=$(get_latest_logfile)
    
    # If the latest log file has changed, update and tail the new log file
    if [ "$current_logfile" != "$latest_logfile" ]; then
      latest_logfile=$current_logfile
      fullpath="/opt/CumulusMX/MXdiags/$latest_logfile"
      
      echo "Loading log file: $latest_logfile"
      
      # Kill the previous tail process if it exists
      if [ -n "$tail_pid" ]; then
        kill "$tail_pid"
      fi
      
      # Tail the new log file in the background
      tail -n +1 -f "$fullpath" &
      
      # Get the PID of the tail process
      tail_pid=$!
    fi
    
    # Sleep for a short period before checking again
    sleep 30
  done
) &

# Wait forever to capture container shutdown command
while true; do
  tail -f /dev/null & wait ${!}
done