#!/usr/bin/env bash
# Create a global "Speedtest fleet" dashboard that aggregates every host
# linked to the "Ookla speedtest by Zabbix agent" template.
#
# Zabbix cannot carry global dashboards in a template export (only host
# dashboards), so this script creates one via the JSON-RPC API instead.
# Widgets use wildcard host patterns matched against item *names*, so any
# host that gets the template linked later shows up automatically.
#
# Usage:
#   ZABBIX_URL=https://zabbix.example.com \
#   ZABBIX_API_TOKEN=xxxx \
#   ./zbx-speedtest-fleet-dashboard.sh [--replace]
#
# ZABBIX_API_TOKEN: create one under Users -> API tokens.
# --replace: overwrite the widget layout of an existing "Speedtest fleet"
#            dashboard instead of refusing to touch it.
#
# Requires: curl, jq
set -euo pipefail

NAME="Speedtest fleet"

: "${ZABBIX_URL:?Set ZABBIX_URL to your Zabbix frontend URL}"
: "${ZABBIX_API_TOKEN:?Set ZABBIX_API_TOKEN (Users -> API tokens)}"

api() {
  curl -sS -X POST "${ZABBIX_URL%/}/api_jsonrpc.php" \
    -H 'Content-Type: application/json-rpc' \
    -H "Authorization: Bearer ${ZABBIX_API_TOKEN}" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
}

pages=$(cat <<'EOF'
[
  {
    "widgets": [
      {
        "type": "tophosts",
        "name": "Latest results",
        "x": 0, "y": 0, "width": 72, "height": 5,
        "fields": [
          {"type": 0, "name": "columns.0.data", "value": 2},
          {"type": 1, "name": "columns.0.name", "value": "Host"},
          {"type": 0, "name": "columns.1.data", "value": 1},
          {"type": 1, "name": "columns.1.name", "value": "Download"},
          {"type": 1, "name": "columns.1.item", "value": "Speedtest: Download"},
          {"type": 0, "name": "columns.2.data", "value": 1},
          {"type": 1, "name": "columns.2.name", "value": "Upload"},
          {"type": 1, "name": "columns.2.item", "value": "Speedtest: Upload"},
          {"type": 0, "name": "columns.3.data", "value": 1},
          {"type": 1, "name": "columns.3.name", "value": "Ping"},
          {"type": 1, "name": "columns.3.item", "value": "Speedtest: Ping"},
          {"type": 0, "name": "columns.4.data", "value": 1},
          {"type": 1, "name": "columns.4.name", "value": "Jitter"},
          {"type": 1, "name": "columns.4.item", "value": "Speedtest: Jitter"},
          {"type": 0, "name": "columns.5.data", "value": 1},
          {"type": 1, "name": "columns.5.name", "value": "Packet loss"},
          {"type": 1, "name": "columns.5.item", "value": "Speedtest: Packet Loss"},
          {"type": 0, "name": "columns.6.data", "value": 1},
          {"type": 1, "name": "columns.6.name", "value": "ISP"},
          {"type": 1, "name": "columns.6.item", "value": "Speedtest: ISP"},
          {"type": 0, "name": "columns.6.display_value_as", "value": 1},
          {"type": 0, "name": "columns.7.data", "value": 1},
          {"type": 1, "name": "columns.7.name", "value": "Server"},
          {"type": 1, "name": "columns.7.item", "value": "Speedtest: Server Name"},
          {"type": 0, "name": "columns.7.display_value_as", "value": 1},
          {"type": 0, "name": "columns.8.data", "value": 1},
          {"type": 1, "name": "columns.8.name", "value": "Age"},
          {"type": 1, "name": "columns.8.item", "value": "Speedtest: Cache age"},
          {"type": 0, "name": "columns.8.decimal_places", "value": 0},
          {"type": 0, "name": "column", "value": 1},
          {"type": 0, "name": "order", "value": 2},
          {"type": 0, "name": "show_lines", "value": 25}
        ]
      },
      {
        "type": "svggraph",
        "name": "Download",
        "x": 0, "y": 5, "width": 36, "height": 6,
        "fields": [
          {"type": 1, "name": "ds.0.hosts.0", "value": "*"},
          {"type": 1, "name": "ds.0.items.0", "value": "Speedtest: Download"},
          {"type": 1, "name": "ds.0.color", "value": "00BFFF"},
          {"type": 0, "name": "ds.0.missingdatafunc", "value": 1},
          {"type": 0, "name": "righty", "value": 0},
          {"type": 1, "name": "reference", "value": "SPDDL"}
        ]
      },
      {
        "type": "svggraph",
        "name": "Upload",
        "x": 36, "y": 5, "width": 36, "height": 6,
        "fields": [
          {"type": 1, "name": "ds.0.hosts.0", "value": "*"},
          {"type": 1, "name": "ds.0.items.0", "value": "Speedtest: Upload"},
          {"type": 1, "name": "ds.0.color", "value": "80FF00"},
          {"type": 0, "name": "ds.0.missingdatafunc", "value": 1},
          {"type": 0, "name": "righty", "value": 0},
          {"type": 1, "name": "reference", "value": "SPDUL"}
        ]
      },
      {
        "type": "svggraph",
        "name": "Latency",
        "x": 0, "y": 11, "width": 36, "height": 6,
        "fields": [
          {"type": 1, "name": "ds.0.hosts.0", "value": "*"},
          {"type": 1, "name": "ds.0.items.0", "value": "Speedtest: Ping"},
          {"type": 1, "name": "ds.0.color", "value": "666699"},
          {"type": 0, "name": "ds.0.missingdatafunc", "value": 1},
          {"type": 1, "name": "ds.1.hosts.0", "value": "*"},
          {"type": 1, "name": "ds.1.items.0", "value": "Speedtest: Jitter"},
          {"type": 1, "name": "ds.1.color", "value": "FFB300"},
          {"type": 0, "name": "ds.1.missingdatafunc", "value": 1},
          {"type": 0, "name": "legend_lines", "value": 2},
          {"type": 0, "name": "righty", "value": 0},
          {"type": 1, "name": "reference", "value": "SPDPG"}
        ]
      },
      {
        "type": "svggraph",
        "name": "Packet loss",
        "x": 36, "y": 11, "width": 36, "height": 6,
        "fields": [
          {"type": 1, "name": "ds.0.hosts.0", "value": "*"},
          {"type": 1, "name": "ds.0.items.0", "value": "Speedtest: Packet Loss"},
          {"type": 1, "name": "ds.0.color", "value": "FF465C"},
          {"type": 0, "name": "ds.0.missingdatafunc", "value": 1},
          {"type": 0, "name": "righty", "value": 0},
          {"type": 1, "name": "reference", "value": "SPDPL"}
        ]
      }
    ]
  }
]
EOF
)

existing=$(api dashboard.get "{\"output\":[\"dashboardid\"],\"filter\":{\"name\":\"${NAME}\"}}" \
  | jq -r '.result[0].dashboardid // empty')

if [ -n "${existing}" ]; then
  if [ "${1:-}" != "--replace" ]; then
    echo "Dashboard \"${NAME}\" already exists (id ${existing})." >&2
    echo "Re-run with --replace to overwrite its widget layout." >&2
    exit 1
  fi
  result=$(api dashboard.update "{\"dashboardid\":\"${existing}\",\"pages\":${pages}}")
else
  result=$(api dashboard.create "{\"name\":\"${NAME}\",\"display_period\":30,\"auto_start\":1,\"private\":0,\"pages\":${pages}}")
fi

if jq -e '.error' >/dev/null <<<"${result}"; then
  echo "Zabbix API error:" >&2
  jq '.error' <<<"${result}" >&2
  exit 1
fi

id=$(jq -r '.result.dashboardids[0]' <<<"${result}")
echo "OK: dashboard \"${NAME}\" (id ${id})"
echo "${ZABBIX_URL%/}/zabbix.php?action=dashboard.view&dashboardid=${id}"
