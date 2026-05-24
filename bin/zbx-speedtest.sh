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

  mkdir -p "$(dirname "$CACHE")"
  local tmp="${CACHE}.new"
  speedtest "${args[@]}" > "$tmp"
  mv "$tmp" "$CACHE"
}

ensure_cache() {
  require jq
  [[ -r "$CACHE" ]] || { echo "ZBX_NOTSUPPORTED: cache missing" >&2; exit 1; }
  jq -e . "$CACHE" >/dev/null 2>&1 \
    || { echo "ZBX_NOTSUPPORTED: cache unparseable" >&2; exit 1; }
}

get() { jq -r "$1" "$CACHE"; }

case "${1:-}" in
  run)             shift; cmd_run "$@" ;;
  -h|--help|help)  usage ;;
  download)        ensure_cache; echo "$(( $(get '.download.bandwidth // 0') * 8 ))" ;;
  upload)          ensure_cache; echo "$(( $(get '.upload.bandwidth   // 0') * 8 ))" ;;
  ping)            ensure_cache; get '.ping.latency  // 0' ;;
  jitter)          ensure_cache; get '.ping.jitter   // 0' ;;
  packetloss)      ensure_cache; get '.packetLoss    // 0' ;;
  server-id)       ensure_cache; get '.server.id            // empty' ;;
  server-name)     ensure_cache; get '.server.name          // empty' ;;
  server-location) ensure_cache; get '.server.location      // empty' ;;
  isp)             ensure_cache; get '.isp                  // empty' ;;
  external-ip)     ensure_cache; get '.interface.externalIp // empty' ;;
  age)             ensure_cache
                   ts=$(get '.timestamp')
                   [[ -n "$ts" && "$ts" != "null" ]] \
                     || { echo "ZBX_NOTSUPPORTED: missing timestamp" >&2; exit 1; }
                   then_s=$(date -u -d "$ts" +%s) \
                     || { echo "ZBX_NOTSUPPORTED: bad timestamp" >&2; exit 1; }
                   age=$(( $(date -u +%s) - then_s ))
                   (( age < 0 )) && age=0
                   echo "$age" ;;
  *)               usage; exit 2 ;;
esac
