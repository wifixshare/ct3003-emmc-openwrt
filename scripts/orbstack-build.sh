#!/usr/bin/env bash

set -euo pipefail

MACHINE="${ORB_MACHINE:-n60-openwrt-build}"
JOBS="${CT3003_JOBS:-12}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_SCRIPT="$SCRIPT_DIR/build-in-orbstack-vm.sh"
ACTION="${1:-start}"

if ! command -v orb >/dev/null 2>&1; then
  echo "OrbStack CLI (orb) was not found." >&2
  exit 1
fi

case "$ACTION" in
  start)
    orb -m "$MACHINE" bash -s -- "$VM_SCRIPT" "$REPO_DIR" "$JOBS" <<'ORB_SCRIPT'
set -euo pipefail
vm_script="$1"
repo_dir="$2"
jobs="$3"
work_root="$HOME/ct3003-emmc-build"
pid_file="$work_root/build.pid"
log_file="$work_root/build.log"

mkdir -p "$work_root"
if [[ -f "$pid_file" ]]; then
  old_pid="$(cat "$pid_file")"
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "CT3003 build is already running (PID $old_pid)."
    echo "Log: $log_file"
    exit 0
  fi
  rm -f "$pid_file"
fi

nohup env CT3003_JOBS="$jobs" \
  bash "$vm_script" "$repo_dir" >"$log_file" 2>&1 </dev/null &
pid=$!
echo "$pid" >"$pid_file"
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo "Build failed to start. Last log lines:" >&2
  tail -80 "$log_file" >&2 || true
  exit 1
fi

echo "CT3003 OrbStack build started (PID $pid, jobs $jobs)."
echo "Log: $log_file"
ORB_SCRIPT
    ;;
  run)
    exec orb -m "$MACHINE" env CT3003_JOBS="$JOBS" \
      bash "$VM_SCRIPT" "$REPO_DIR"
    ;;
  status)
    orb -m "$MACHINE" bash -lc '
      work_root="$HOME/ct3003-emmc-build"
      pid_file="$work_root/build.pid"
      if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "running (PID $(cat "$pid_file"))"
      else
        echo "not running"
      fi
      tail -40 "$work_root/build.log" 2>/dev/null || true
    '
    ;;
  log)
    orb -m "$MACHINE" bash -lc 'tail -200 "$HOME/ct3003-emmc-build/build.log"'
    ;;
  *)
    echo "Usage: $0 [start|run|status|log]" >&2
    exit 2
    ;;
esac
