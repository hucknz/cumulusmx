#!/bin/bash
set -e

# MXWeather.sh - container entrypoint for CumulusMX
# - Applies runtime TZ if provided
# - Derives a sensible LANG/LC_* from TZ when LANG is not provided by the user
# - Exports locale env vars so . NET Core uses the expected culture (can be overridden via docker run -e)
# - Starts nginx and CumulusMX (dotnet) and tails the MXDiags log to stdout with tail -F
# - Handles SIGTERM to shut down cleanly and persist config files

# --- Timezone handling (apply at container start so docker run -e TZ=...  is honored) ---
if [ -n "$TZ" ]; then
  if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    echo "Timezone set to $TZ"
  else
    echo "Warning: timezone '/usr/share/zoneinfo/$TZ' not found.  Leaving image default (TZ=${TZ:-ETC/UTC})."
  fi
else
  echo "TZ not set; using image default TZ=${TZ:-ETC/UTC}"
fi

# --- Locale handling ---

# Helper: normalize locale to include . UTF-8 suffix
_normalize_lang() {
  local l="$1"
  if [ -z "$l" ]; then
    echo ""
    return 0
  fi
  # If already has charset, normalize utf8 variants to UTF-8
  if echo "$l" | grep -qE '\.'; then
    echo "$l" | sed -E 's/\.[Uu][Tt][Ff]-? 8$/. UTF-8/'
  else
    echo "${l}.UTF-8"
  fi
}

# Helper: map TZ to locale
_map_tz_to_locale() {
  case "$1" in
    "Pacific/Auckland"|"NZ"|"Antarctica/McMurdo")
      echo "en_NZ.UTF-8" ;;
    "Australia/Sydney"|"Australia/Melbourne"|"Australia/Brisbane"|"Australia/Perth"|"Australia/Adelaide")
      echo "en_AU. UTF-8" ;;
    "Europe/London"|"Europe/Guernsey"|"Europe/Jersey"|"Europe/Isle_of_Man"|"Europe/Dublin")
      echo "en_GB. UTF-8" ;;
    "America/New_York"|"America/Detroit"|"America/Toronto"|"America/Indiana"*)
      echo "en_US. UTF-8" ;;
    "America/Chicago"|"America/Winnipeg"|"America/Mexico_City")
      echo "en_US. UTF-8" ;;
    "America/Los_Angeles"|"America/Vancouver"|"America/Anchorage")
      echo "en_US. UTF-8" ;;
    "Asia/Tokyo"|"Asia/Okinawa")
      echo "ja_JP.UTF-8" ;;
    "Asia/Shanghai"|"Asia/Chongqing"|"Asia/Hong_Kong"|"Asia/Singapore")
      echo "zh_CN. UTF-8" ;;
    "Asia/Seoul")
      echo "ko_KR.UTF-8" ;;
    "Europe/Paris"|"Europe/Brussels"|"Europe/Zurich"|"Europe/Luxembourg")
      echo "fr_FR. UTF-8" ;;
    "Europe/Berlin"|"Europe/Amsterdam"|"Europe/Vienna")
      echo "de_DE. UTF-8" ;;
    "Pacific/Honolulu")
      echo "en_US.UTF-8" ;;
    *)
      case "$1" in
        Europe/*) echo "en_GB.UTF-8" ;;
        America/*) echo "en_US. UTF-8" ;;
        Pacific/*|Australia/*) echo "en_AU.UTF-8" ;;
        Asia/*) echo "en_US. UTF-8" ;;
        Africa/*) echo "en_GB.UTF-8" ;;
        Atlantic/*|Indian/*|Arctic/*|Antarctica/*) echo "en_US. UTF-8" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

# Determine effective locale
effective_lang=""

# Check if user explicitly provided LANG (not C or C.UTF-8)
if [ -n "$LANG" ] && [ "$LANG" != "C. UTF-8" ] && [ "$LANG" != "C" ]; then
  # User explicitly provided LANG - use it
  effective_lang=$(_normalize_lang "$LANG")
  echo "User-supplied LANG: $effective_lang"
else
  # Derive from TZ
  if [ -n "$TZ" ]; then
    derived=$(_map_tz_to_locale "$TZ")
    if [ -n "$derived" ]; then
      effective_lang="$derived"
      echo "Derived locale from TZ: $effective_lang"
    fi
  fi
  
  # Fallback to default
  if [ -z "$effective_lang" ]; then
    effective_lang="en_GB.UTF-8"
    echo "Using default locale: $effective_lang"
  fi
fi

# Export locale variables for this script and child processes
export LANG="$effective_lang"
export LC_ALL="$effective_lang"
export LC_CTYPE="$effective_lang"

# Calculate LANGUAGE from LANG
lang_short="${LANG%%.*}"      # e.g., en_NZ
lang_code="${lang_short%%_*}" # e.g., en
export LANGUAGE="${lang_short}:${lang_code}"

# Write to /etc/default/locale so new shells pick it up
cat > /etc/default/locale <<EOF
LANG="$LANG"
LC_ALL="$LC_ALL"
LANGUAGE="$LANGUAGE"
EOF

# Write to /etc/environment for system-wide persistence
grep -v "^LANG=\|^LC_ALL=\|^LANGUAGE=\|^LC_CTYPE=" /etc/environment > /tmp/env.new 2>/dev/null || touch /tmp/env.new
cat >> /tmp/env.new <<EOF
LANG="$LANG"
LC_ALL="$LC_ALL"
LC_CTYPE="$LC_CTYPE"
LANGUAGE="$LANGUAGE"
EOF
cat /tmp/env.new > /etc/environment
rm -f /tmp/env.new

echo "=== Locale Configuration ==="
echo "LANG=$LANG"
echo "LC_ALL=$LC_ALL"
echo "LC_CTYPE=$LC_CTYPE"
echo "LANGUAGE=$LANGUAGE"
echo "============================"

# Verify locale is available
if locale -a 2>/dev/null | grep -qi "^${LANG%%.*}"; then
  echo "Locale $LANG is available in system"
else
  echo "WARNING: Locale $LANG may not be fully available"
  echo "Available locales:"
  locale -a 2>/dev/null | head -20
fi

# Ensure . NET uses system globalization (set AFTER locale configuration)
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=${DOTNET_SYSTEM_GLOBALIZATION_INVARIANT:-false}

# --- End runtime locale handling ---

# --- Migration logic
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

# Start NGINX web server
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