#!/bin/bash
set -e

# Set timezone at container start so runtime TZ env var is honored
if [ -n "$TZ" ]; then
  if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    echo "Timezone set to $TZ"
  else
    echo "Warning: timezone '/usr/share/zoneinfo/$TZ' not found. Leaving default timezone (${TZ:-ETC/UTC})."
  fi
else
  echo "TZ not set; using default timezone from image: ${TZ:-ETC/UTC}"
fi

# Migrate v3 to v4 functionality

# Enables migration if the environment variable is set
if [ "$MIGRATE" != "false" ]; then
  echo "Migration enabled. Begin migration checks..."

  # Checks if there is more than 1 file in the data folder (indicates new install or existing)
  if [ "$(ls -A /opt/CumulusMX/data/ | wc -l)" -gt 1 ] || [ "$MIGRATE" == "force" ]; then 
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

# Copy Web Support files (ignore errors if none)
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ || true

# Copy Public Web templates (ignore errors if none)
cp -Rn /tmp/web/* /opt/CumulusMX/web/ || true

# SIGTERM handler copies files to config folder when container stops and kills child processes
term_handler() {
  echo "Received SIGTERM, shutting down..."
  # kill dotnet (if running)
  if [ -n "$dotnet_pid" ]; then
    kill -SIGTERM "$dotnet_pid" 2>/dev/null || true
    wait "$dotnet_pid" 2>/dev/null || true
  fi
  # kill tail (if running)
  if [ -n "$tail_pid" ]; then
    kill -SIGTERM "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
  fi

  sleep 1
  # Persist files if present
  if [ -f "/opt/CumulusMX/Cumulus.ini" ]; then
    cp -f /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/
  fi
  if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
    cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/
  fi

  exit 143; # 128 + 15 -- SIGTERM
}

# Setup trap for SIGTERM
trap 'term_handler' SIGTERM

# Run application (move Cumulus files back if present)
if [ -f "/opt/CumulusMX/config/UniqueId.txt" ]; then
  cp -f /opt/CumulusMX/config/UniqueId.txt /opt/CumulusMX/
fi
if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
  cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
fi

# Start CumulusMX in background and remember its PID
dotnet /opt/CumulusMX/CumulusMX.dll >> /var/log/nginx/CumulusMX.log 2>&1 &
dotnet_pid="$!"
echo "Started CumulusMX with PID $dotnet_pid"

# Tail the single static log file using tail -F and make it the foreground process so Docker captures continuous output.
# Using exec replaces the shell with tail so the container's main process is tail and docker logs will stream live output
LOGFILE="/opt/CumulusMX/MXdiags/MxDiags.log"

# Start tail -F as foreground; tail -F will wait for the file to appear and will follow rotations/recreations.
# We capture its PID only for the shutdown handler (when exec is used PID tracking isn't needed, but we keep guard)
tail -n +1 -F "$LOGFILE" &
tail_pid=$!

# Wait for dotnet to exit; keep the container running until dotnet stops.
# When dotnet exits, allow short delay for logs to flush, then exit (which will terminate tail via SIGTERM trap).
wait "$dotnet_pid"
echo "CumulusMX process exited; allowing 1s for logs to flush."
sleep 1

# If dotnet has exited we should exit the script which will trigger TERM handler and stop tail
exit 0
