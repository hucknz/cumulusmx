#!/bin/bash
set -e

# --- Timezone handling ---
if [ -n "$TZ" ]; then
  if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    echo "Timezone set to $TZ"
  else
    echo "Warning: timezone '/usr/share/zoneinfo/$TZ' not found."
  fi
else
  echo "TZ not set; using image default"
fi

# --- Locale handling ---

# Helper: find the actual locale string from locale -a (exact match required!)
_find_available_locale() {
  local want="$1"
  local base="${want%%.*}"
  
  # Try common patterns in order of preference
  local match
  
  # 1. Try exact match (case-sensitive)
  match=$(locale -a 2>/dev/null | grep -x "$want" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  # 2. Try base. utf8 (most common in locales-all)
  match=$(locale -a 2>/dev/null | grep -x "${base}.utf8" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  # 3. Try base. UTF-8 (less common but possible)
  match=$(locale -a 2>/dev/null | grep -x "${base}.UTF-8" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  # 4. Try just base without charset
  match=$(locale -a 2>/dev/null | grep -x "$base" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  # 5. Try case-insensitive match as last resort
  match=$(locale -a 2>/dev/null | grep -ix "$want" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  # 6. Try base with any suffix (case-insensitive)
  match=$(locale -a 2>/dev/null | grep -i "^${base}" | head -n1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  
  return 1
}

# Helper: map TZ to locale base (without charset)
_map_tz_to_locale() {
  case "$1" in
    "Pacific/Auckland"|"NZ"|"Antarctica/McMurdo") echo "en_NZ" ;;
    "Australia/"*) echo "en_AU" ;;
    "Europe/London"|"Europe/Dublin"|"Europe/Guernsey"|"Europe/Jersey"|"Europe/Isle_of_Man") echo "en_GB" ;;
    "America/"*) echo "en_US" ;;
    "Asia/Tokyo"|"Asia/Okinawa") echo "ja_JP" ;;
    "Asia/Shanghai"|"Asia/Hong_Kong"|"Asia/Singapore") echo "zh_CN" ;;
    "Asia/Seoul") echo "ko_KR" ;;
    "Europe/Paris"|"Europe/Brussels"|"Europe/Zurich"|"Europe/Luxembourg") echo "fr_FR" ;;
    "Europe/Berlin"|"Europe/Amsterdam"|"Europe/Vienna") echo "de_DE" ;;
    Europe/*) echo "en_GB" ;;
    Pacific/*|Australia/*) echo "en_AU" ;;
    Asia/*) echo "en_US" ;;
    Africa/*) echo "en_GB" ;;
    *) echo "en_GB" ;;
  esac
}

echo "=== Locale Configuration ==="
echo "Initial environment: LANG='$LANG' TZ='$TZ'"

# Determine desired locale base (without charset)
desired_base=""

if [ -n "$LANG" ] && [ "$LANG" != "C. UTF-8" ] && [ "$LANG" != "C" ]; then
  # User provided LANG - extract base
  desired_base="${LANG%%.*}"
  echo "User-supplied LANG base: $desired_base"
else
  # Derive from TZ
  if [ -n "$TZ" ]; then
    desired_base=$(_map_tz_to_locale "$TZ")
    echo "Derived from TZ: $desired_base"
  fi
  
  # Fallback
  if [ -z "$desired_base" ]; then
    desired_base="en_GB"
    echo "Using default: $desired_base"
  fi
fi

# Find the actual available locale string
actual_locale=$(_find_available_locale "${desired_base}. utf8")
if [ -z "$actual_locale" ]; then
  actual_locale=$(_find_available_locale "${desired_base}. UTF-8")
fi
if [ -z "$actual_locale" ]; then
  actual_locale=$(_find_available_locale "$desired_base")
fi

if [ -z "$actual_locale" ]; then
  echo "WARNING: Could not find locale for '$desired_base' in system"
  echo "Available locales matching '${desired_base}':"
  locale -a 2>/dev/null | grep -i "$desired_base" || echo "(none found)"
  echo ""
  echo "Falling back to C.UTF-8"
  actual_locale="C.UTF-8"
else
  echo "Found available locale: $actual_locale"
fi

# Export ALL locale variables with the exact string from locale -a
export LANG="$actual_locale"
export LC_ALL="$actual_locale"
export LC_CTYPE="$actual_locale"
export LC_NUMERIC="$actual_locale"
export LC_TIME="$actual_locale"
export LC_COLLATE="$actual_locale"
export LC_MONETARY="$actual_locale"
export LC_MESSAGES="$actual_locale"
export LC_PAPER="$actual_locale"
export LC_NAME="$actual_locale"
export LC_ADDRESS="$actual_locale"
export LC_TELEPHONE="$actual_locale"
export LC_MEASUREMENT="$actual_locale"
export LC_IDENTIFICATION="$actual_locale"

# Calculate LANGUAGE (use base without charset)
lang_short="${desired_base}"
lang_code="${lang_short%%_*}"
export LANGUAGE="${lang_short}:${lang_code}"

# Persist to config files (so new shells inherit the locale)
cat > /etc/default/locale <<EOF
LANG="$LANG"
LC_ALL="$LC_ALL"
LANGUAGE="$LANGUAGE"
EOF

# Update /etc/environment for system-wide persistence
grep -v "^LANG=\|^LC_\|^LANGUAGE=" /etc/environment 2>/dev/null > /tmp/envfile.tmp || touch /tmp/envfile.tmp
cat >> /tmp/envfile.tmp <<EOF
LANG="$LANG"
LC_ALL="$LC_ALL"
LC_CTYPE="$LC_CTYPE"
LC_NUMERIC="$LC_NUMERIC"
LC_TIME="$LC_TIME"
LC_COLLATE="$LC_COLLATE"
LC_MONETARY="$LC_MONETARY"
LC_MESSAGES="$LC_MESSAGES"
LC_PAPER="$LC_PAPER"
LC_NAME="$LC_NAME"
LC_ADDRESS="$LC_ADDRESS"
LC_TELEPHONE="$LC_TELEPHONE"
LC_MEASUREMENT="$LC_MEASUREMENT"
LC_IDENTIFICATION="$LC_IDENTIFICATION"
LANGUAGE="$LANGUAGE"
EOF
cat /tmp/envfile.tmp > /etc/environment
rm -f /tmp/envfile.tmp

echo "=== Final Locale Settings ==="
echo "LANG=$LANG"
echo "LC_ALL=$LC_ALL"
echo "LANGUAGE=$LANGUAGE"
echo "============================"

# Verify locale is working
echo "Verifying locale (output from 'locale' command):"
locale
echo "============================"

# Ensure . NET uses system globalization
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