#!/bin/bash
set -e

# MXWeather.sh - container entrypoint for CumulusMX
# - Applies runtime TZ if provided
# - Derives a sensible LANG/LC_* from TZ when LANG is not provided by the user
# - Exports locale env vars so .NET Core uses the expected culture (can be overridden via docker run -e)
# - Starts nginx and CumulusMX (dotnet) and tails the MXDiags log to stdout with tail -F
# - Handles SIGTERM to shut down cleanly and persist config files

# Ensure .NET uses system globalization (if image default or user hasn't set)
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=${DOTNET_SYSTEM_GLOBALIZATION_INVARIANT:-false}

# --- Timezone handling (apply at container start so docker run -e TZ=... is honored) ---
if [ -n "$TZ" ]; then
  if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    echo "Timezone set to $TZ"
  else
    echo "Warning: timezone '/usr/share/zoneinfo/$TZ' not found. Leaving image default (TZ=${TZ:-ETC/UTC})."
  fi
else
  echo "TZ not set; using image default TZ=${TZ:-ETC/UTC}"
fi

# --- Derive LANG from TZ if LANG is not explicitly provided ---
# Users can still override LANG/LC_* by passing -e LANG=... at runtime.
# This heuristic maps common timezone regions/cities to a sensible default locale.
# It's intentionally conservative: if a good mapping cannot be determined we leave LANG alone
# (so image default or user-supplied LANG applies).
if [ -z "${LANG}" ] || [ "${LANG}" = "C.UTF-8" ] || [ "${LANG}" = "C" ]; then
  derived_lang=""
  if [ -n "$TZ" ]; then
    # Normalize TZ (strip POSIX-style prefixes, if any)
    tz_short=$(basename "$TZ")

    # Common explicit mappings for well-known tz names
    case "$TZ" in
      "Pacific/Auckland"|"NZ"|"Antarctica/McMurdo")
        derived_lang="en_NZ.UTF-8"
        ;;
      "Australia/Sydney"|"Australia/Melbourne"|"Australia/Brisbane"|"Australia/Perth"|"Australia/Adelaide")
        derived_lang="en_AU.UTF-8"
        ;;
      "Europe/London"|"Europe/Guernsey"|"Europe/Jersey"|"Europe/Isle_of_Man"|"Europe/Dublin")
        derived_lang="en_GB.UTF-8"
        ;;
      "America/New_York"|"America/Detroit"|"America/Toronto"|"America/Indiana"*)
        derived_lang="en_US.UTF-8"
        ;;
      "America/Chicago"|"America/Winnipeg"|"America/Mexico_City")
        derived_lang="en_US.UTF-8"
        ;;
      "America/Los_Angeles"|"America/Vancouver"|"America/Anchorage")
        derived_lang="en_US.UTF-8"
        ;;
      "Asia/Tokyo"|"Asia/Okinawa")
        # Japan uses ja_JP, but many apps may expect en; choose ja_JP for accuracy
        derived_lang="ja_JP.UTF-8"
        ;;
      "Asia/Shanghai"|"Asia/Chongqing"|"Asia/Hong_Kong"|"Asia/Singapore")
        derived_lang="zh_CN.UTF-8"
        ;;
      "Asia/Seoul")
        derived_lang="ko_KR.UTF-8"
        ;;
      "Europe/Paris"|"Europe/Brussels"|"Europe/Zurich"|"Europe/Luxembourg")
        derived_lang="fr_FR.UTF-8"
        ;;
      "Europe/Berlin"|"Europe/Amsterdam"|"Europe/Vienna")
        derived_lang="de_DE.UTF-8"
        ;;
      "Pacific/Honolulu")
        derived_lang="en_US.UTF-8"
        ;;
      *)
        # Fallback heuristics by continent prefix
        case "$TZ" in
          Europe/*)
            # Use en_GB as a conservative English default for Europe; users can override to a local language
            derived_lang="en_GB.UTF-8"
            ;;
          America/*)
            derived_lang="en_US.UTF-8"
            ;;
          Pacific/*)
            # assume Australian English as general Pacific default, except NZ handled above
            derived_lang="en_AU.UTF-8"
            ;;
          Australia/*)
            derived_lang="en_AU.UTF-8"
            ;;
          Asia/*)
            # default to en_US for Asia unless a specific mapping is provided above
            derived_lang="en_US.UTF-8"
            ;;
          Africa/*)
            derived_lang="en_GB.UTF-8"
            ;;
          Atlantic/*|Indian/*|Arctic/*|Antarctica/*)
            derived_lang="en_US.UTF-8"
            ;;
          *)
            derived_lang=""
            ;;
        esac
        ;;
    esac
  fi

  if [ -n "$derived_lang" ]; then
    # Only set LANG if the derived locale exists on the system (avoid setting an unavailable locale)
    if locale -a 2>/dev/null | grep -i -q "^${derived_lang%%.*}"; then
      export LANG=$derived_lang
      export LANGUAGE=${LANGUAGE:-${LANG%%.*}:en}
      export LC_ALL=${LC_ALL:-$LANG}
      echo "Derived locale from TZ: LANG=$LANG"
    else
      # If the exact derived locale isn't available check for the UTF-8 canonical name in locale -a
      if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "$(echo $derived_lang | tr '[:upper:]' '[:lower:]' | sed 's/\.utf-8//')"; then
        # pick the matching available locale (case-insensitive)
        match=$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep "$(echo $derived_lang | tr '[:upper:]' '[:lower:]' | sed 's/\.utf-8//')" | head -n1)
        export LANG="$match"
        export LANGUAGE=${LANGUAGE:-${match%%.*}:en}
        export LC_ALL=${LC_ALL:-$LANG}
        echo "Derived locale from TZ (case-insensitive match): LANG=$LANG"
      else
        echo "Derived LANG would be $derived_lang but that locale is not present in the image. Leaving LANG unset so image default/user-supplied LANG applies."
      fi
    fi
  else
    echo "Could not derive a locale from TZ ($TZ); leaving LANG to image default or user-supplied value."
  fi
else
  echo "LANG is already set to '$LANG' — skipping derivation from TZ."
fi

# --- Migration logic (unchanged except minor robustness) ---
# Enables migration if the environment variable is set
if [ "$MIGRATE" != "false" ]; then
  echo "Migration enabled. Begin migration checks..."

  # Checks if there is more than 1 file in the data folder (indicates new install or existing)
  if [ "$(ls -A /opt/CumulusMX/data/ 2>/dev/null | wc -l)" -gt 1 ] || [ "$MIGRATE" == "force" ]; then 
    echo "Multiple files detected. Checking if migration has already been completed..."

    # Checks to see if data has already been migrated and skips migration if it has. 
    if { [ ! -f "/opt/CumulusMX/config/.migrated" ] && [ ! -f "/opt/CumulusMX/config/.nodata" ]; } || [ "$MIGRATE" == "force" ]; then 
      if [ "$MIGRATE" == "force" ]; then
        echo "Migration is being forced. Backing up files..."
      else 
        echo "No previous migration detected. Backing up files..."
      fi

      # Backup Cumulus.ini file
      if [ -f /opt/CumulusMX/config/Cumulus.ini ]; then
        cp -R /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/config/Cumulus-v3.ini.bak
        echo "Backed up Cumulus.ini"
      fi

      # Backup data files
      mkdir -p /opt/CumulusMX/backup/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/backup/datav3 || true
      echo "Backed up data folder"

      # Copy Cumulus.ini to root if present
      if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
        cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
        echo "Copied Cumulus.ini file to root"
      fi

      # Copy data files to datav3 for migration
      mkdir -p /opt/CumulusMX/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/datav3 || true
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
      mkdir -p /opt/CumulusMX/config
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
    mkdir -p /opt/CumulusMX/config
    touch /opt/CumulusMX/config/.nodata
    echo "No data detected... Skipping migration."
  fi
  
else
  echo "Migration is disabled... Skipping migration."
fi

# Start NGINX web server
service nginx start

# Copy Web Support files (ignore errors if none)
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ 2>/dev/null || true

# Copy Public Web templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/ 2>/dev/null || true

# --- Signal handling and process management ---
dotnet_pid=""
tail_pid=""

term_handler() {
  echo "Received SIGTERM, shutting down..."
  # signal dotnet to exit
  if [ -n "$dotnet_pid" ] && kill -0 "$dotnet_pid" 2>/dev/null; then
    kill -SIGTERM "$dotnet_pid" 2>/dev/null || true
    wait "$dotnet_pid" 2>/dev/null || true
  fi
  # stop tail if running
  if [ -n "$tail_pid" ] && kill -0 "$tail_pid" 2>/dev/null; then
    kill -SIGTERM "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
  fi

  # persist config files if present
  if [ -f "/opt/CumulusMX/Cumulus.ini" ]; then
    cp -f /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/ 2>/dev/null || true
  fi
  if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
    cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/ 2>/dev/null || true
  fi

  exit 143; # 128 + 15 -- SIGTERM
}

trap 'term_handler' SIGTERM

# Start the application: restore config files into place if present
if [ -f "/opt/CumulusMX/config/UniqueId.txt" ]; then
  cp -f /opt/CumulusMX/config/UniqueId.txt /opt/CumulusMX/
fi
if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
  cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
fi

# Start CumulusMX in background and capture pid
dotnet /opt/CumulusMX/CumulusMX.dll >> /var/log/nginx/CumulusMX.log 2>&1 &
dotnet_pid="$!"
echo "Starting CumulusMX (PID $dotnet_pid)..."

# Tail the single static log file using tail -F so it will wait for the file and follow recreations/rotations.
LOGFILE="/opt/CumulusMX/MXdiags/MxDiags.log"

# Start tail -F in background and capture PID so the TERM handler can stop it.
# tail -F will wait for the file if it doesn't exist and will follow it if rotated/recreated.
tail -n +1 -F "$LOGFILE" &
tail_pid=$!

# Wait for dotnet to exit; when it does, allow brief time for logs and then exit to let the container stop.
wait "$dotnet_pid"
echo "CumulusMX process exited; allowing 1s for logs to flush."
sleep 1

# Clean exit (term_handler will run on SIGTERM, but on natural exit we should also kill tail)
if [ -n "$tail_pid" ] && kill -0 "$tail_pid" 2>/dev/null; then
  kill -SIGTERM "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
fi

exit 0
