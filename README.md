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

Then on the Zabbix server, build the template per the [Template overview](#template-overview)
below, export it to `templates/template_speedtest.yaml`, and link it to each host.
(A reference YAML export will be committed once built — `templates/` is currently
a placeholder.)

## Per-host pinning (optional)

Once you've watched auto-select for a few days, pin to the most consistent
server:

```bash
echo 'SPEEDTEST_SERVER_ID=23969' | sudo tee /etc/default/zabbix-speedtest
sudo systemctl restart zabbix-speedtest.timer
```

`speedtest -L` lists nearby servers.

## Template overview

Items (all **Zabbix agent (active)**):

| Key | Type | Units | Interval |
|---|---|---|---|
| `speedtest.download` | unsigned | `bps` | 2h |
| `speedtest.upload` | unsigned | `bps` | 2h |
| `speedtest.ping` | float | `ms` | 2h |
| `speedtest.jitter` | float | `ms` | 2h |
| `speedtest.packetloss` | float | `%` | 2h |
| `speedtest.server.id` / `.name` / `.location` | character | — | 2h |
| `speedtest.isp` / `speedtest.wan.ip` | character | — | 2h |
| `speedtest.age` | unsigned | `s` | **10m** (watchdog) |

Macros (host-overridable):

| Macro | Default | Meaning |
|---|---|---|
| `{$SPEEDTEST.MAX_AGE}` | `10800` | Cache stale threshold (s) |
| `{$SPEEDTEST.DL_LOW}` | `100000000` | Download alert threshold (bps) |
| `{$SPEEDTEST.UL_LOW}` | `8000000` | Upload alert threshold (bps) |
| `{$SPEEDTEST.LATENCY_HIGH}` | `50` | Latency alert (ms) |
| `{$SPEEDTEST.PLOSS_HIGH}` | `1` | Packet loss alert (%) |

Triggers use `avg(..., 3)` to require 3 consecutive bad runs (~6h) before
firing, so one flaky test won't page.

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
