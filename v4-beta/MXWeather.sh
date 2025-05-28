#!/bin/bash

# Migrate v3 to v4 functionality

# Enables migration if the environment variable is set
if [ "$MIGRATE" != "false" ]; then
echo "Migration enabled. Begin migration checks..."

  # Checks if there is more than 1 file in the data folder (indicates new install or existing)
  if [ "$(ls -A /opt/CumulusMX/data/ | wc -l)" -gt 1 ]|| [ "$MIGRATE" == "force" ]; then 
  echo "Multiple files detected. Checking if migration has already been completed..."

    # Checks to see if data has already been migrated and skips migration if it has. 
    if [ ! -f "/opt/CumulusMX/config/.migrated" ] && [ ! -f "/opt/CumulusMX/config/.nodata" ] || [ "$MIGRATE" == "force" ]; then 
      if [ "$MIGRATE" == "force" ]; then
        echo "Migration is being forced. Backing up files..."
      else 
       echo "No previous migration detected. Backing up files..."
      fi

      # Backup Cumulus.ini file
      cp -R /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/config/Cumulus-v3.ini.bak
      echo "Backed up Cumulus.ini"

      # Backup data files
      mkdir -p /opt/CumulusMX/backup/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/backup/datav3
      echo "Backed up data folder"

      # Copy Cumulus.ini to root
      cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
      echo "Copied Cumulus.ini file to root"

      # Copy data files to datav3 for migration
      mkdir /opt/CumulusMX/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/datav3
      echo "Copied data files to migration folder"

      # Run migration script
      echo "Running migration task..."
      expect <<EOF
spawn dotnet MigrateData3to4.dll $MIGRATE_CUSTOM_LOG_FILES
expect "Press a Enter to continue, or Ctrl-C to exit"
send "\r"
expect "Press Enter to exit"
send "\r"
expect eof
EOF

      # Leave a file to indicate the migration has been completed
      touch /opt/CumulusMX/config/.migrated

      # Copy UniqueID file to config folder if it exists

      if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
        cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/
      fi
      echo "Migration completed. Starting CumulusMX..."

    else 
      # If the .migrated or .nodata file already exists it skips the migration. 
      echo "Migration has already been done... Skipping migration."
    fi

  else
    # No data detected so there's nothing to migrate. Leave a file to indicate the migration has been completed. 
    touch /opt/CumulusMX/config/.nodata
    echo "No data detected... Skipping migration."
  fi
  
else
  echo "Migration is disabled... Skipping migration."
fi

# Start NGINX web server
service nginx start

# Copy Web Support files
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Copy Public Web templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/

# WebSocket Override Setup
echo "Setting up WebSocket override for HTTPS compatibility..."

# Wait for web files to be ready
sleep 2

# Find and modify HTML files to include the WebSocket override
find /opt/CumulusMX/publicweb -name "*.htm" -o -name "*.html" | while read file; do
    # Check if the script is already included
    if ! grep -q "websocket-override.js" "$file"; then
        # Insert the script tag before </head>
        sed -i 's|</head>|<script src="/js/websocket-override.js"></script>\n</head>|' "$file"
        echo "Added WebSocket override to: $(basename $file)"
    fi
done

echo "WebSocket override setup completed"

# Handle container shutdown
pid=0

# SIGTERM handler copies files to config folder when container stops
term_handler() {
  if [ $pid -ne 0 ]; then
    kill -SIGTERM "$pid"
    wait "$pid"
    sleep 2
    if [ -f "/opt/CumulusMX/Cumulus.ini" ]; then
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
if [ -f "/opt/CumulusMX/config/UniqueId.txt" ]; then
  cp -f /opt/CumulusMX/config/UniqueId.txt /opt/CumulusMX/
fi
if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
  cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
fi
dotnet /opt/CumulusMX/CumulusMX.dll >> /var/log/nginx/CumulusMX.log &
pid="$!"
echo "Starting CumulusMX..."

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
