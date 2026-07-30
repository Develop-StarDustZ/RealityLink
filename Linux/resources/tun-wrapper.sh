#!/bin/sh

set -u
umask 077

if [ "$#" -ne 6 ]; then
  echo "usage: tun-wrapper core config log pid stop reload" >&2
  exit 64
fi

source_core="$1"
config="$2"
log="$3"
pid_file="$4"
stop_file="$5"
reload_file="$6"
child=""
log_checks=0
secure_core="$(mktemp /tmp/realitylink-core.XXXXXX)" || exit 1
install -m 0700 "$source_core" "$secure_core" || exit 1
core="$secure_core"

start_core() {
  "$core" run -c "$config" </dev/null >"$log" 2>&1 &
  child=$!
  printf '%s\n' "$child" >"$pid_file"
}

stop_core() {
  if [ -n "$child" ]; then
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
}

cleanup() {
  stop_core
  rm -f "$secure_core"
}

trap 'cleanup; exit 0' HUP INT TERM EXIT
rm -f "$stop_file" "$reload_file"
start_core

while true; do
  if [ -e "$stop_file" ]; then
    stop_core
    trap - EXIT
    rm -f "$secure_core"
    exit 0
  fi
  if [ -e "$reload_file" ]; then
    rm -f "$reload_file"
    stop_core
    start_core
  fi
  if ! kill -0 "$child" 2>/dev/null; then
    wait "$child"
    status=$?
    trap - EXIT
    rm -f "$secure_core"
    exit "$status"
  fi
  log_checks=$((log_checks + 1))
  if [ "$log_checks" -ge 20 ]; then
    log_checks=0
    log_size="$(wc -c <"$log" 2>/dev/null || printf '0')"
    if [ "$log_size" -gt 5242880 ]; then
      tail -c 1048576 "$log" >"$log.trim" 2>/dev/null || true
      cat "$log.trim" >"$log" 2>/dev/null || true
      rm -f "$log.trim"
    fi
  fi
  sleep 0.25
done
