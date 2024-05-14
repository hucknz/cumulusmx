#!/bin/bash

# Migrate v3 to v4 functionality

# Checks if there is more than 1 file in the data folder (indicates new install or existing)
if [ "$(ls -A /opt/CumulusMX/data/ | wc -l)" -gt 1 ]; then 
# Checks for datav3 folder. If it doesn't exist then creates it and copies v3 files to it and makes a backup. 
    if [ ! -f "/opt/CumulusMX/config/.migrated" ]; then 
      # Backup Cumulus.ini
      cp /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/config/Cumulus.ini.bak
      # Copy Cumulus.ini to root
      cp /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
      # Backup data files
      mkdir -p /opt/CumulusMX/backup/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/backup/datav3
      # Copy data files to datav3 for migration
      mkdir /opt/CumulusMX/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/datav3
      # Run migration script
      expect <<EOF
spawn dotnet MigrateData3to4.dll
expect "Press a Enter to continue, or Ctrl-C to exit"
send "\r"
expect "Press Enter to exit"
send "\r"
expect eof
EOF
      # Copy migrated Cumulus.ini file back to config folder
      cp /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/Cumulus.ini
      # Leave a file to indicate the migration has been completed
      touch /opt/CumulusMX/config/.migrated
    else 
      # If the .migrated file already exists it skips the migration. 
      echo "Migration already completed."
    fi
else
  # No data detected so there's nothing to migrate. 
    echo "No data detected. Skipping migration."
fi


# Start nginx web server
service nginx start

# Copy Web Support Files
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Copy Public Web Templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/

set -x
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

# wait forever
while true
do
  tail -f /dev/null & wait ${!}
done
