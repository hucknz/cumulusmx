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
if [ -z "${LANG}" ] || [ "${LANG}" = "C.UTF-8" ] || [ "${LANG}" = "C" ]; then
  derived_lang=""
  if [ -n "$TZ" ]; then
    tz_short=$(basename "$TZ")
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
        case "$TZ" in
          Europe/*) derived_lang="en_GB.UTF-8" ;;
          America/*) derived_lang="en_US.UTF-8" ;;
          Pacific/*) derived_lang="en_AU.UTF-8" ;;
          Australia/*) derived_lang="en_AU.UTF-8" ;;
          Asia/*) derived_lang="en_US.UTF-8" ;;
          Africa/*) derived_lang="en_GB.UTF-8" ;;
          Atlantic/*|Indian/*|Arctic/*|Antarctica/*) derived_lang="en_US.UTF-8" ;;
          *) derived_lang="" ;;
        esac
        ;;
    esac
  fi

  if [ -n "$derived_lang" ]; then
    if locale -a 2>/dev/null | grep -i -q "^${derived_lang%%.*}"; then
      export LANG=$derived_lang
      export LANGUAGE=${LANGUAGE:-${LANG%%.*}:en}
      export LC_ALL=${LC_ALL:-$LANG}
      echo "Derived locale from TZ: LANG=$LANG"
    else
      if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "$(echo $derived_lang | tr '[:upper:]' '[:lower:]' | sed 's/\.utf-8//')"; then
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

# --- Migration logic (unchanged) ---
if [ "$MIGRATE" != "false" ]; then
  echo "Migration enabled. Begin migration checks..."
  if [ "$(ls -A /opt/CumulusMX/data/ 2>/dev/null | wc -l)" -gt 1 ] || [ "$MIGRATE" == "force" ]; then
    echo "Multiple files detected. Checking if migration has already been completed..."
    if { [ ! -f "/opt/CumulusMX/config/.migrated" ] && [ ! -f "/opt/CumulusMX/config/.nodata" ]; } || [ "$MIGRATE" == "force" ]; then
      if [ "$MIGRATE" == "force" ]; then
        echo "Migration is being forced. Backing up files..."
      else
        echo "No previous migration detected. Backing up files..."
      fi
      if [ -f /opt/CumulusMX/config/Cumulus.ini ]; then
        cp -R /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/config/Cumulus-v3.ini.bak
        echo "Backed up Cumulus.ini"
      fi
      mkdir -p /opt/CumulusMX/backup/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/backup/datav3 || true
      echo "Backed up data folder"
      if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
        cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
        echo "Copied Cumulus.ini file to root"
      fi
      mkdir -p /opt/CumulusMX/datav3
      cp -R /opt/CumulusMX/data/* /opt/CumulusMX/datav3 || true
      echo "Copied data files to migration folder"
      echo "Running migration task..."
      expect <<EOF
spawn dotnet MigrateData3to4.dll $MIGRATE_CUSTOM_LOG_FILES
expect "Press a Enter to continue, or Ctrl-C to exit"
send "\r"
expect "Press Enter to exit"
send "\r"
expect eof
EOF
      mkdir -p /opt/CumulusMX/config
      touch /opt/CumulusMX/config/.migrated
      if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
        cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/
      fi
      echo "Migration completed. Starting CumulusMX..."
    else
      echo "Migration has already been done... Skipping migration."
    fi
  else
    mkdir -p /opt/CumulusMX/config
    touch /opt/CumulusMX/config/.nodata
    echo "No data detected... Skipping migration."
  fi
else
  echo "Migration is disabled... Skipping migration."
fi

# Start NGINX web server (no nginx config changes performed here)
service nginx start

# Copy Web Support files (ignore errors if none)
cp -Rn /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ 2>/dev/null || true

# Copy Public Web templates
cp -Rn /tmp/web/* /opt/CumulusMX/web/ 2>/dev/null || true

# Support specifying CumulusMX port. Defaults to 8998. 
: "${PORT:=8998}"
export PORT
echo "Using internal CumulusMX port: ${PORT}"

# --- Signal handling and process management ---
dotnet_pid=""
tail_pid=""

term_handler() {
  echo "Received SIGTERM, shutting down..."
  if [ -n "$dotnet_pid" ] && kill -0 "$dotnet_pid" 2>/dev/null; then
    kill -SIGTERM "$dotnet_pid" 2>/dev/null || true
    wait "$dotnet_pid" 2>/dev/null || true
  fi
  if [ -n "$tail_pid" ] && kill -0 "$tail_pid" 2>/dev/null; then
    kill -SIGTERM "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
  fi
  if [ -f "/opt/CumulusMX/Cumulus.ini" ]; then
    cp -f /opt/CumulusMX/Cumulus.ini /opt/CumulusMX/config/ 2>/dev/null || true
  fi
  if [ -f "/opt/CumulusMX/UniqueId.txt" ]; then
    cp -f /opt/CumulusMX/UniqueId.txt /opt/CumulusMX/config/ 2>/dev/null || true
  fi
  exit 143;
}

trap 'term_handler' SIGTERM

# Restore config files if present
if [ -f "/opt/CumulusMX/config/UniqueId.txt" ]; then
  cp -f /opt/CumulusMX/config/UniqueId.txt /opt/CumulusMX/
fi
if [ -f "/opt/CumulusMX/config/Cumulus.ini" ]; then
  cp -f /opt/CumulusMX/config/Cumulus.ini /opt/CumulusMX/
fi

# Start CumulusMX and capture pid (pass -port)
dotnet /opt/CumulusMX/CumulusMX.dll -port "${PORT}" >> /var/log/nginx/CumulusMX.log 2>&1 &
dotnet_pid="$!"
echo "Starting CumulusMX (PID $dotnet_pid) on port ${PORT}..."

# Tail the MXDiags log
LOGFILE="/opt/CumulusMX/MXdiags/MxDiags.log"
tail -n +1 -F "$LOGFILE" &
tail_pid=$!

# Wait for dotnet to exit; when it does, allow brief time for logs and then exit to let the container stop.
wait "$dotnet_pid"
echo "CumulusMX process exited; allowing 1s for logs to flush."
sleep 1

# Clean exit: kill tail if running
if [ -n "$tail_pid" ] && kill -0 "$tail_pid" 2>/dev/null; then
  kill -SIGTERM "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
fi

exit 0