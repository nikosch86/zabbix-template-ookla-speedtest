# Ookla speedtest by Zabbix agent

Zabbix 7.2 template for monitoring ISP performance from each location using
the official **Ookla Speedtest CLI**. A systemd timer runs the test
periodically and caches the JSON result on disk; the local Zabbix agent
serves cached fields via UserParameter — so the existing **active-agent**
items already configured across your fleet just pick up another template.

- Tested with Zabbix **7.2 LTS** on Debian/Ubuntu
- Decoupled: the timer runs the test (~30s), the agent reads the JSON cache
  in milliseconds — no agent timeouts
- Per-host pinning of an Ookla server via `SPEEDTEST_SERVER_ID` (optional;
  auto-select by default)
- Cache-staleness watchdog item (`speedtest.age`) so a hung speedtest fires
  one alert, not five — the four performance triggers depend on it
- Baseline-anomaly triggers (`baselinedev` / `baselinewma`) flag deviations
  from the past 7 days, independent of the static floors
- Fleet dashboard script creates a global dashboard aggregating every host
  linked to the template — Zabbix can't ship global dashboards inside a
  template export

Author: [@nikosch86](https://github.com/nikosch86) ·
Source: <https://github.com/nikosch86/zabbix-template-ookla-speedtest>

## Requirements

- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) (**not** the
  abandoned `sivel/speedtest-cli` Python tool)
- `jq`
- `zabbix-agent2`
- `systemd` 235+
- **A synchronised clock** — `chronyd` or `systemd-timesyncd` running.
  The `speedtest.age` item compares the cache timestamp to the local
  clock; if NTP later step-corrects a drifted clock, age values will
  jump until the next refresh.

## Install (per location)

```bash
# Ookla CLI
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install speedtest jq

# Script
sudo install -m 755 bin/zbx-speedtest.sh /usr/local/bin/zbx-speedtest.sh

# systemd timer
sudo install -m 644 systemd/zabbix-speedtest.service /etc/systemd/system/
sudo install -m 644 systemd/zabbix-speedtest.timer   /etc/systemd/system/
sudo install -m 644 systemd/zabbix-speedtest.default /etc/default/zabbix-speedtest
sudo systemctl daemon-reload
sudo systemctl enable --now zabbix-speedtest.timer

# Agent UserParameters
sudo install -m 644 zabbix_agent2.d/speedtest.conf /etc/zabbix/zabbix_agent2.d/
sudo systemctl restart zabbix-agent2
```

Then on the Zabbix server, import `template_speedtest.yaml`
(*Data collection → Templates → Import*) and link
**Ookla speedtest by Zabbix agent** to each host.

## Per-host server pinning (optional)

Once you've watched auto-select for a few days, pin to the most consistent
server. `speedtest -L` lists nearby candidates; verify a chosen one with
`speedtest -s <id>` before committing.

```bash
echo 'SPEEDTEST_SERVER_ID=23969' | sudo tee /etc/default/zabbix-speedtest
sudo systemctl start zabbix-speedtest.service
```

Use `systemctl start zabbix-speedtest.service` — not `restart …timer` —
since restarting the timer only re-arms its schedule, it doesn't trigger
a fresh run. Confirm the new server stuck with
`sudo -u zabbix /usr/local/bin/zbx-speedtest.sh server-id`.

## Template overview

Template name: **Ookla speedtest by Zabbix agent** (group `Templates/Network`).

### Items

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

The underlying data only changes every 2h (timer cadence), but the agent
and timer clocks can't be aligned, so items poll every 5m. A refreshed
cache becomes visible in Zabbix within ~5m; storage stays flat.

`speedtest.wan.ip` stores the host's public IP (90d history). If that's
sensitive in your environment, disable the item on the linked host.

### Macros

| Macro | Default | Description |
|---|---|---|
| `{$SPEEDTEST.MAX_AGE}` | `10800` | Max cache age in seconds before the staleness trigger fires (default 3h, timer cadence is 2h). |
| `{$SPEEDTEST.DL_LOW}` | `100000000` | Floor for download alert, in bps (default 100 Mbps). |
| `{$SPEEDTEST.UL_LOW}` | `8000000` | Floor for upload alert, in bps (default 8 Mbps). |
| `{$SPEEDTEST.LATENCY_HIGH}` | `50` | Ceiling for ping alert, in ms. |
| `{$SPEEDTEST.PLOSS_HIGH}` | `1` | Ceiling for packet-loss alert, in %. |
| `{$SPEEDTEST.DEV}` | `2.5` | Baseline deviation factor for anomaly triggers (standard deviations from the 7-day baseline; higher = less sensitive). |
| `{$SPEEDTEST.ANOMALY.MARGIN}` | `0.2` | Minimum fractional move from the 7-day baseline average required (on top of `{$SPEEDTEST.DEV}` σ) before an anomaly trigger fires. `0.2` = 20%; stops trivial dips on a very stable line from alerting. |

### Triggers

All eight triggers are suppressed while `Speedtest cache stale` is active,
so a hung speedtest fires one alert instead of fanning out.

| Name | Severity | Expression (summary) |
|---|---|---|
| Speedtest cache stale | Average | `last(speedtest.age) > {$SPEEDTEST.MAX_AGE}` |
| Download below floor | Warning | `avg(speedtest.download, 6h) < {$SPEEDTEST.DL_LOW}` |
| Upload below floor | Warning | `avg(speedtest.upload, 6h) < {$SPEEDTEST.UL_LOW}` |
| Latency high | Warning | `avg(speedtest.ping, 6h) > {$SPEEDTEST.LATENCY_HIGH}` |
| Packet loss high | Average | `avg(speedtest.packetloss, 6h) > {$SPEEDTEST.PLOSS_HIGH}` |
| Download anomalously low | Warning | `baselinedev(download, …) > {$SPEEDTEST.DEV} and last < baselinewma * (1 - {$SPEEDTEST.ANOMALY.MARGIN})` |
| Upload anomalously low | Warning | `baselinedev(upload, …) > {$SPEEDTEST.DEV} and last < baselinewma * (1 - {$SPEEDTEST.ANOMALY.MARGIN})` |
| Latency anomalously high | Warning | `baselinedev(ping, …) > {$SPEEDTEST.DEV} and last > baselinewma * (1 + {$SPEEDTEST.ANOMALY.MARGIN})` |

The four performance triggers (`*below floor` / `*high`) average over 6h
so a single flaky run can't fire them. The three anomaly triggers require
**both** a `{$SPEEDTEST.DEV}`-sigma deviation **and** at least a
`{$SPEEDTEST.ANOMALY.MARGIN}` (20%) move from the 7-day baseline average,
so a trivial dip on a very stable connection stays quiet. They auto-recover
once the metric returns toward baseline.

### Dashboard

The template ships a one-page `Speedtest` dashboard: SVG graphs for
bandwidth, latency (ping and jitter), and packet loss plus single-value
widgets for ISP, WAN IP, server name, location, and cache age. The graphs
follow the dashboard's time-period selector (top right) and connect across
gaps, so the sparse per-run samples render as a continuous line.

Because a speedtest runs only every ~2h, set the time-period selector to
a wider range (e.g. **Last 7 days**) for a meaningful view — at the
Zabbix default of *Last 1 hour* the graphs look empty or show a single
dot. Zabbix remembers the selected range per user; a default range cannot
be baked into the dashboard.

## Fleet dashboard (all hosts)

Cross-host template graphs are gone in Zabbix 7, and global dashboards
cannot be carried in a template export — so the fleet-wide view ships as
a script that creates it through the Zabbix API:

```bash
ZABBIX_URL=https://zabbix.example.com \
ZABBIX_API_TOKEN=xxxx \
./bin/zbx-speedtest-fleet-dashboard.sh
```

Create the token under *Users → API tokens* for a user with write access
to dashboards; needs `curl` and `jq`. The script creates a public
**Speedtest fleet** dashboard with:

- **Latest results** — one row per host: download, upload, ping, jitter,
  packet loss, ISP, server, and cache age, sorted by download speed
- **Download / Upload / Latency / Packet loss** graphs overlaying every
  host, with ping and jitter combined in the latency graph

The widgets match hosts by wildcard pattern against the template's item
names, so a host linked to the template later shows up automatically —
the dashboard needs no maintenance as the fleet grows. If a dashboard
named `Speedtest fleet` already exists, the script refuses to touch it;
pass `--replace` to overwrite its widget layout. As with the host
dashboard, pick a wide time range (e.g. **Last 7 days**).
