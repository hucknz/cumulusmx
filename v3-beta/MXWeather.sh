#!/bin/bash

# Start nginx web server
service nginx start

# Copy Web Support Files
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Copy Public Web Templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/

pid=0

# SIGTERM-handler
term_handler() {
  if [ $pid -ne 0 ]; then
    kill -SIGTERM "$pid"
    wait "$pid"
    sleep 2
    cp -f /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/
  fi
  exit 143; # 128 + 15 -- SIGTERM
}

# setup handlers
trap 'kill ${!}; term_handler' SIGTERM

# run application
cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
mono /opt/CumulusMX/CumulusMX.exe >> /var/log/nginx/CumulusMX.log &
pid="$!"

# Find the latest log file
logfile="$(ls -1 /opt/CumulusMX/MXdiags | grep -E '^[0-9]{8}-[0-9]{6}\.txt$' | sort | tail -n 1)"

# Send log file to stdout
echo "Loading log file: $logfile"
sleep 2
tail -n +1 -f "/opt/CumulusMX/MXdiags/$logfile"

# wait forever
while true
do
  tail -f /dev/null & wait ${!}
done
