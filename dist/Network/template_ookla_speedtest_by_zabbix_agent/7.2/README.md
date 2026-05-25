# Ookla speedtest by Zabbix agent

Monitor ISP performance from each host using the official **Ookla Speedtest
CLI**. A systemd timer runs the test periodically on each host and caches
the JSON result on disk; the local Zabbix agent serves cached fields via
UserParameter, so active-agent items return in milliseconds and never time
out.

- Cache-staleness watchdog item (`speedtest.age`) so a hung speedtest fires
  one alert, not five — the four performance triggers depend on it
- Baseline-anomaly triggers (`baselinedev` / `baselinewma`) flag deviations
  from the past 7 days, independent of the static floors
- Per-host pinning of an Ookla server via `SPEEDTEST_SERVER_ID` (optional;
  auto-select by default)

Author: [@nikosch86](https://github.com/nikosch86) ·
Source: <https://github.com/nikosch86/zabbix-template-ookla-speedtest>

## Requirements

- Zabbix **7.2 LTS** or later
- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) (**not** the
  abandoned `sivel/speedtest-cli` Python tool)
- `jq`
- `zabbix-agent2`
- `systemd` 235+
- **A synchronised clock** — `chronyd` or `systemd-timesyncd` running.
  The `speedtest.age` item compares the cache timestamp to the local
  clock; if NTP later step-corrects a drifted clock, age values will
  jump until the next refresh.

## Tested versions

- Ookla Speedtest CLI **1.2.x**

## Setup

Run on each host that should be monitored:

```bash
# Ookla CLI
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install speedtest jq

# Helper script
sudo install -m 755 files/zbx-speedtest.sh /usr/local/bin/zbx-speedtest.sh

# systemd timer
sudo install -m 644 files/zabbix-speedtest.service /etc/systemd/system/
sudo install -m 644 files/zabbix-speedtest.timer   /etc/systemd/system/
sudo install -m 644 files/zabbix-speedtest.default /etc/default/zabbix-speedtest
sudo systemctl daemon-reload
sudo systemctl enable --now zabbix-speedtest.timer

# Agent UserParameters
sudo install -m 644 files/speedtest.conf /etc/zabbix/zabbix_agent2.d/
sudo systemctl restart zabbix-agent2
```

Then in the Zabbix frontend: *Data collection → Templates → Import* the
`template_ookla_speedtest_by_zabbix_agent.yaml`, then link **Ookla
speedtest by Zabbix agent** to each monitored host. Adjust the
`{$SPEEDTEST.*}` macros at the host level if the location's expected
baseline differs from the defaults.

### Per-host server pinning (optional)

Once you've watched auto-select for a few days, pin to the most consistent
server. `speedtest -L` lists nearby candidates; verify a chosen one with
`speedtest -s <id>` before committing.

```bash
echo 'SPEEDTEST_SERVER_ID=23969' | sudo tee /etc/default/zabbix-speedtest
sudo systemctl start zabbix-speedtest.service
```

Use `systemctl start zabbix-speedtest.service` — not `restart …timer` —
since restarting the timer only re-arms its schedule, it doesn't trigger
a fresh run.

## Items

All items use **Zabbix agent (active)**. Numeric items apply *Discard
unchanged with heartbeat* (6h for numerics, 24h for strings) so the polled
cache produces flat storage between refreshes — except `speedtest.age`,
which must tick every poll for the staleness trigger to evaluate.

| Key | Value type | Units | Interval |
|---|---|---|---|
| `speedtest.age` | unsigned | `s` | 10m |
| `speedtest.download` | unsigned | `bps` | 5m |
| `speedtest.upload` | unsigned | `bps` | 5m |
| `speedtest.ping` | float | `ms` | 5m |
| `speedtest.jitter` | float | `ms` | 5m |
| `speedtest.packetloss` | float | `%` | 5m |
| `speedtest.isp` | character | — | 5m |
| `speedtest.wan.ip` | character | — | 5m |
| `speedtest.server.id` | character | — | 5m |
| `speedtest.server.name` | character | — | 5m |
| `speedtest.server.location` | character | — | 5m |

`speedtest.wan.ip` stores the host's public IP (90d history). If that's
sensitive in your environment, disable the item on the linked host.

## Macros

| Macro | Default | Description |
|---|---|---|
| `{$SPEEDTEST.MAX_AGE}` | `10800` | Max cache age in seconds before the staleness trigger fires (default 3h, timer cadence is 2h). |
| `{$SPEEDTEST.DL_LOW}` | `100000000` | Floor for download alert, in bps (default 100 Mbps). |
| `{$SPEEDTEST.UL_LOW}` | `8000000` | Floor for upload alert, in bps (default 8 Mbps). |
| `{$SPEEDTEST.LATENCY_HIGH}` | `50` | Ceiling for ping alert, in ms. |
| `{$SPEEDTEST.PLOSS_HIGH}` | `1` | Ceiling for packet-loss alert, in %. |
| `{$SPEEDTEST.DEV}` | `2.5` | Baseline deviation factor for anomaly triggers (standard deviations from the 7-day baseline; higher = less sensitive). |

## Triggers

All eight triggers are suppressed while `Speedtest cache stale` is active,
so a hung speedtest fires one alert instead of fanning out.

| Name | Severity | Expression (summary) |
|---|---|---|
| Speedtest cache stale | Average | `last(speedtest.age) > {$SPEEDTEST.MAX_AGE}` |
| Download below floor | Warning | `avg(speedtest.download, 6h) < {$SPEEDTEST.DL_LOW}` |
| Upload below floor | Warning | `avg(speedtest.upload, 6h) < {$SPEEDTEST.UL_LOW}` |
| Latency high | Warning | `avg(speedtest.ping, 6h) > {$SPEEDTEST.LATENCY_HIGH}` |
| Packet loss high | Average | `avg(speedtest.packetloss, 6h) > {$SPEEDTEST.PLOSS_HIGH}` |
| Download anomalously low | Warning | `baselinedev(download, 6h:now/h, "d", 7) > {$SPEEDTEST.DEV} and last < baselinewma` |
| Upload anomalously low | Warning | `baselinedev(upload, 6h:now/h, "d", 7) > {$SPEEDTEST.DEV} and last < baselinewma` |
| Latency anomalously high | Warning | `baselinedev(ping, 6h:now/h, "d", 7) > {$SPEEDTEST.DEV} and last > baselinewma` |

The four performance triggers (`*below floor` / `*high`) average over 6h
so a single flaky run can't fire them. The three anomaly triggers are
`manual_close: YES` because baseline math can stay noisy after the
underlying issue clears.

## Dashboard

The template ships a one-page `Speedtest` dashboard: SVG graphs for
bandwidth, latency, and packet loss (24h window) plus single-value
widgets for ISP, WAN IP, server name, location, and cache age.
