# Zabbix Speedtest (multi-location ISP monitoring)

Run Ookla Speedtest periodically on each location, cache the result as JSON,
and let the local Zabbix agent serve fields via UserParameter — so the
existing **active-agent** items already configured across your fleet just
pick up another template.

- Tested with Zabbix **7.2 LTS** on Debian/Ubuntu
- Decoupled: a systemd timer runs the test (~30s), the agent reads a fresh
  JSON cache in milliseconds — no agent timeouts
- Per-host pinning of an Ookla server via `SPEEDTEST_SERVER_ID` (optional;
  auto-select by default)
- Cache-staleness watchdog item (`speedtest.age`) so a hung speedtest is
  visible as a trigger, not as flat-line graph

## Dependencies

- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) (**not** the
  abandoned `sivel/speedtest-cli` Python tool)
- `jq`
- `zabbix-agent2` (or classic `zabbix-agent`)
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
(*Data collection → Templates → Import*) and link it to each host.
The [Template overview](#template-overview) below summarises what's inside.

## Per-host pinning (optional)

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

Items (all **Zabbix agent (active)**):

| Key | Type | Units | Interval |
|---|---|---|---|
| `speedtest.download` | unsigned | `bps` | 5m |
| `speedtest.upload` | unsigned | `bps` | 5m |
| `speedtest.ping` | float | `ms` | 5m |
| `speedtest.jitter` | float | `ms` | 5m |
| `speedtest.packetloss` | float | `%` | 5m |
| `speedtest.server.id` / `.name` / `.location` | character | — | 5m |
| `speedtest.isp` / `speedtest.wan.ip` | character | — | 5m |
| `speedtest.age` | unsigned | `s` | **10m** (watchdog) |

The data only changes every 2h (timer cadence), but agent and timer clocks
can't be aligned, so items poll the cache every 5m and use *Discard
unchanged with heartbeat* preprocessing (6h for numerics, 24h for strings)
to avoid storing repeats. A refreshed cache becomes visible in Zabbix
within ~5m; storage stays flat. `speedtest.age` is exempt — it must tick
every poll for the staleness trigger to evaluate.

Macros (host-overridable):

| Macro | Default | Meaning |
|---|---|---|
| `{$SPEEDTEST.MAX_AGE}` | `10800` | Cache stale threshold (s) |
| `{$SPEEDTEST.DL_LOW}` | `100000000` | Download alert threshold (bps) |
| `{$SPEEDTEST.UL_LOW}` | `8000000` | Upload alert threshold (bps) |
| `{$SPEEDTEST.LATENCY_HIGH}` | `50` | Latency alert (ms) |
| `{$SPEEDTEST.PLOSS_HIGH}` | `1` | Packet loss alert (%) |

Triggers use `avg(/.../X, 6h)` so a single flaky run can't fire them. The
four performance triggers depend on `Speedtest cache stale`, so a hung
speedtest surfaces as one alert instead of five.

## Multi-location comparison

Cross-host template graphs are gone in Zabbix 7. Build a **Dashboard** with
one *graph widget* per location pinning the same items — that's the modern
view of "ISP speed across all locations".

## Credits

Architecture borrows from
[pschmitt/zabbix-template-speedtest](https://github.com/pschmitt/zabbix-template-speedtest)
(cache + UserParameter). Script logic borrows from
[sebastian13/zabbix-template-speedtest](https://github.com/sebastian13/zabbix-template-speedtest)
(Ookla JSON parsing, packetloss, server-id selection).
