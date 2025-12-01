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

# --- Robust runtime locale handling ---
# Priority for effective LANG:
# 1) If LANG explicitly provided (and not C/C.UTF-8), use it (ensure .UTF-8)
# 2) Else derive LANG from TZ using mapping logic below (only if locale exists)
# 3) Else fall back to image default LANG or en_GB.UTF-8

# Image default LANG (set at build time in Dockerfile). We treat LC_ALL equal to this as "not explicitly provided"
IMAGE_DEFAULT_LANG="en_GB.UTF-8"

# Helper: normalize locale string to include .UTF-8 suffix if missing
_normalize_lang() {
  local l="$1"
  if [ -z "$l" ]; then
    echo ""
    return 0
  fi
  # If it already contains a dot (i.e. charset), respect it; if user passed e.g. en_US.utf8 normalize to .UTF-8
  if echo "$l" | grep -qE '\.'; then
    # Normalize common utf8 variants to UTF-8
    echo "$l" | sed -E 's/[Uu][Tt][Ff]-?8/UTF-8/'
  else
    echo "${l}.UTF-8"
  fi
}

# Helper: check whether a locale exists on the system (case-insensitive, tolerate .utf8 / .UTF-8 / no-suffix)
_locale_exists() {
  local want="$1"
  if [ -z "$want" ]; then
    return 1
  fi
  local base="${want%%.*}"             # en_US
  local want_lower
  want_lower=$(echo "$want" | tr '[:upper:]' '[:lower:]' | sed 's/\.utf-8//')
  if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "^${want_lower}\$"; then
    return 0
  fi
  # If locale -a lists entries like en_US.utf8 or en_US.UTF-8 or en_US, try to match base
  if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "^${base,,}" ; then
    return 0
  fi
  # Try contains match for cases like en_US.utf8 (some systems append modifiers)
  if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q "${want_lower}"; then
    return 0
  fi
  return 1
}

# Helper: attempt to find a matching locale string from locale -a and return it (first found)
_find_locale_match() {
  local want="$1"
  local want_lower
  want_lower=$(echo "$want" | tr '[:upper:]' '[:lower:]' | sed 's/\.utf-8//')
    # Prefer exact match first
  match="$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -E "^${want_lower}(\.|$)" | head -n1 || true)"
  if [ -n "$match" ]; then
    # Return in original case as in locale -a (we'll re-use the exact entry)
    locale -a 2>/dev/null | grep -i "^$match$" | head -n1
    return 0
  fi
  # Fallback: grep contains
  match="$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -i "$want_lower" | head -n1 || true)"
  if [ -n "$match" ]; then
    locale -a 2>/dev/null | grep -i "$match" | head -n1
    return 0
  fi
  return 1
}

# Helper: map TZ -> reasonable locale (extendable)
_map_tz_to_locale() {
  case "$1" in
    "Pacific/Auckland"|"NZ"|"Antarctica/McMurdo")
      echo "en_NZ.UTF-8" ;;
    "Australia/Sydney"|"Australia/Melbourne"|"Australia/Brisbane"|"Australia/Perth"|"Australia/Adelaide")
      echo "en_AU.UTF-8" ;;
    "Europe/London"|"Europe/Guernsey"|"Europe/Jersey"|"Europe/Isle_of_Man"|"Europe/Dublin")
      echo "en_GB.UTF-8" ;;
    "America/New_York"|"America/Detroit"|"America/Toronto"|"America/Indiana"*)
      echo "en_US.UTF-8" ;;
    "America/Chicago"|"America/Winnipeg"|"America/Mexico_City")
      echo "en_US.UTF-8" ;;
    "America/Los_Angeles"|"America/Vancouver"|"America/Anchorage")
      echo "en_US.UTF-8" ;;
    "Asia/Tokyo"|"Asia/Okinawa")
      echo "ja_JP.UTF-8" ;;
    "Asia/Shanghai"|"Asia/Chongqing"|"Asia/Hong_Kong"|"Asia/Singapore")
      echo "zh_CN.UTF-8" ;;
    "Asia/Seoul")
      echo "ko_KR.UTF-8" ;;
    "Europe/Paris"|"Europe/Brussels"|"Europe/Zurich"|"Europe/Luxembourg")
      echo "fr_FR.UTF-8" ;;
    "Europe/Berlin"|"Europe/Amsterdam"|"Europe/Vienna")
      echo "de_DE.UTF-8" ;;
    "Pacific/Honolulu")
      echo "en_US.UTF-8" ;;
    *)
      case "$1" in
        Europe/*) echo "en_GB.UTF-8" ;;
        America/*) echo "en_US.UTF-8" ;;
        Pacific/*|Australia/*) echo "en_AU.UTF-8" ;;
        Asia/*) echo "en_US.UTF-8" ;;
        Africa/*) echo "en_GB.UTF-8" ;;
        Atlantic/*|Indian/*|Arctic/*|Antarctica/*) echo "en_US.UTF-8" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

# Determine effective LANG
# Consider LANG set and not equal to C/C.UTF-8 as explicit
effective_lang=""
if [ -n "$LANG" ] && [ "$LANG" != "C.UTF-8" ] && [ "$LANG" != "C" ]; then
  # Normalize user-provided LANG (ensure UTF-8)
  tmp_lang=$(_normalize_lang "$LANG")
  # If the normalized locale exists, use it; else try to match case-insensitively; else still use provided value with a warning.
  if _locale_exists "$tmp_lang"; then
    # Try to find a canonical entry from locale -a for better compatibility
    match=$(_find_locale_match "$tmp_lang" || true)
    if [ -n "$match" ]; then
      effective_lang="$match"
    else
      effective_lang="$tmp_lang"
    fi
    echo "User-supplied LANG detected and present in image: LANG=$effective_lang"
  else
    # Try fallback forms: sometimes locale -a has entries without suffix or different case
    base="${tmp_lang%%.*}"
    if _locale_exists "$base"; then
      match=$(_find_locale_match "$base" || true)
      if [ -n "$match" ]; then
        effective_lang="$match"
        echo "User-supplied LANG matched case-insensitively to available locale: LANG=$effective_lang"
      fi
    fi
    if [ -z "$effective_lang" ]; then
      # Not found in image, still set LANG to normalized user value (this may produce warnings when formatting if locale not present)
      effective_lang="$tmp_lang"
      echo "Warning: user-supplied LANG '$LANG' normalized to '$effective_lang' but that locale was not found in the image; formatting may fall back to defaults."
    fi
  fi
else
  # No explicit LANG provided by user; attempt to derive from TZ
  derived=""
  if [ -n "$TZ" ]; then
    derived=$(_map_tz_to_locale "$TZ")
  fi

  if [ -n "$derived" ]; then
    # Normalize and check availability
    derived_norm=$(_normalize_lang "$derived")
    if _locale_exists "$derived_norm"; then
      match=$(_find_locale_match "$derived_norm" || true)
      if [ -n "$match" ]; then
        effective_lang="$match"
      else
        effective_lang="$derived_norm"
      fi
      echo "Derived locale from TZ: LANG=$effective_lang"
    else
      # Try base mapping match
      base="${derived_norm%%.*}"
      if _locale_exists "$base"; then
        match=$(_find_locale_match "$base" || true)
        if [ -n "$match" ]; then
          effective_lang="$match"
          echo "Derived locale from TZ (base match): LANG=$effective_lang"
        fi
      fi
      if [ -z "$effective_lang" ]; then
        echo "Derived LANG would be $derived_norm but that locale is not present in the image; leaving LANG unset so image default/user-supplied LANG applies."
      fi
    fi
  else
    echo "Could not derive a locale from TZ ($TZ); leaving LANG to image default or user-supplied value."
  fi
fi

# If still no effective_lang, fall back to environment LANG or image default
if [ -z "$effective_lang" ]; then
  if [ -n "$LANG" ]; then
    # Ensure .UTF-8 suffix if possible
    effective_lang=$(_normalize_lang "$LANG")
  else
    effective_lang="$IMAGE_DEFAULT_LANG"
  fi
fi

# Export LANG (ensure it's set for the rest of the script/processes)
export LANG="$effective_lang"

# Decide whether LC_ALL was explicitly provided at runtime.
# We treat LC_ALL as NOT explicit if it's empty or equals the image default LANG (IMAGE_DEFAULT_LANG).
lc_all_explicit=false
if [ -n "${LC_ALL+x}" ] && [ -n "$LC_ALL" ] && [ "$LC_ALL" != "$IMAGE_DEFAULT_LANG" ]; then
  lc_all_explicit=true
fi

# Export LC_ALL: if user explicitly provided LC_ALL, respect it; otherwise mirror LANG
if [ "$lc_all_explicit" = true ]; then
  echo "LC_ALL is explicitly provided at runtime: LC_ALL=$LC_ALL (will be respected)"
else
  export LC_ALL="${LC_ALL:-$LANG}"
  echo "Setting LC_ALL to match effective LANG: LC_ALL=$LC_ALL"
fi

# Export LANGUAGE if not explicitly set: format "<lang_short>:<lang_code>", e.g. en_US:en
if [ -z "${LANGUAGE+x}" ] || [ -z "$LANGUAGE" ]; then
  lang_short="${LANG%%.*}"   # en_US
  lang_code="${lang_short%%_*}" # en
  export LANGUAGE="${lang_short}:${lang_code}"
  echo "Setting LANGUAGE to: LANGUAGE=$LANGUAGE"
else
  echo "LANGUAGE is provided in environment: LANGUAGE=$LANGUAGE"
fi

# Persist locale to /etc/default/locale for other tools/shells if running as root
if [ "$(id -u)" -eq 0 ]; then
  cat >/etc/default/locale <<EOF
LANG=$LANG
LANGUAGE=$LANGUAGE
LC_ALL=$LC_ALL
EOF
  echo "/etc/default/locale written with LANG=$LANG LANGUAGE=$LANGUAGE LC_ALL=$LC_ALL"
else
  echo "Not running as root; skipping write to /etc/default/locale (but variables exported in this process)."
fi

# --- End runtime locale handling ---

# --- Migration logic  ---
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