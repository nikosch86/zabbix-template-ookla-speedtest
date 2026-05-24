#!/usr/bin/env bash
# Run Ookla Speedtest and cache the JSON. Read subcommands serve cached
# fields to Zabbix via UserParameter.

set -euo pipefail

CACHE="${SPEEDTEST_CACHE:-/var/lib/zabbix-speedtest/speedtest.json}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

  run [--server-id ID]   Run speedtest, refresh cache. Honors \$SPEEDTEST_SERVER_ID.
  download | upload      bits/s
  ping | jitter          ms
  packetloss             %
  server-id | server-name | server-location
  isp | external-ip
  age                    Seconds since cache timestamp
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" >&2; exit 1; }
}

get() {
  require jq
  [[ -r "$CACHE" ]] || { echo "ZBX_NOTSUPPORTED: cache missing" >&2; exit 1; }
  jq -r "$1" "$CACHE"
}

cmd_run() {
  local sid="${SPEEDTEST_SERVER_ID:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --server-id) sid="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
  done

  require speedtest
  speedtest --version 2>&1 | grep -q "Speedtest by Ookla" \
    || { echo "[ERR] need official Ookla Speedtest CLI" >&2; exit 1; }

  local args=(--accept-license --accept-gdpr --format=json)
  [[ "$sid" =~ ^[0-9]+$ ]] && args+=(--server-id="$sid")

  install -d -m 755 "$(dirname "$CACHE")"
  local tmp="${CACHE}.new"
  speedtest "${args[@]}" > "$tmp"
  mv "$tmp" "$CACHE"
}

case "${1:-}" in
  run)             shift; cmd_run "$@" ;;
  download)        echo "$(( $(get '.download.bandwidth // 0') * 8 ))" ;;
  upload)          echo "$(( $(get '.upload.bandwidth   // 0') * 8 ))" ;;
  ping)            get '.ping.latency  // 0' ;;
  jitter)          get '.ping.jitter   // 0' ;;
  packetloss)      get '.packetLoss    // 0' ;;
  server-id)       get '.server.id           // empty' ;;
  server-name)     get '.server.name         // empty' ;;
  server-location) get '.server.location     // empty' ;;
  isp)             get '.isp                 // empty' ;;
  external-ip)     get '.interface.externalIp // empty' ;;
  age)             ts=$(get '.timestamp')
                   then_s=$(date -u -d "$ts" +%s)
                   echo $(( $(date -u +%s) - then_s )) ;;
  -h|--help|help)  usage ;;
  *)               usage; exit 2 ;;
esac
