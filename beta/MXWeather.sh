#!/bin/bash

# Migrate v3 to v4 functionality

# Enables migration if the environment variable is set
if [ "$MIGRATE" ]; then
echo "Migration enabled. Starting migration..."
  # Checks to see if data has already been migrated and skips if it has. 
  if [ ! -f "/opt/CumulusMX/config/.migrated" ]; then 
    # Backup Cumulus.ini file
    cp -R /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/config/Cumulus-v3.ini.bak
    # Copy Cumulus.ini to root
    cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
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
    # Leave a file to indicate the migration has been completed
    touch /opt/CumulusMX/config/.migrated
    # Copy UniqueID file to config folder
    cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/
  else 
    # If the .migrated file already exists it skips the migration. 
    echo "Migration already completed... Skipping migration."
  fi
else
 echo "Migration not enabled... Skipping migration."
fi

# Start NGINX web server
service nginx start

# Copy Web Support files
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Copy Public Web templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/

set -x
pid=0

# SIGTERM-handler
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
cp -f /opt/CumulusMX/config/UniqueId.txt /opt/CumulusMX/
cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
dotnet /opt/CumulusMX/CumulusMX.dll >> /var/log/nginx/CumulusMX.log &
pid="$!"

# Wait forever
while true
do
  tail -f /dev/null & wait ${!}
done
