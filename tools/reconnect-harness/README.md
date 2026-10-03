tools/reconnect-harness — E20-12: reconnect latency (disconnect/dead event to session Ready) from timestamped logs.

`run.rb` parses marker lines, one latency per episode (first `disconnected`/`dead` until next
`ready`; later events inside an open episode are ignored), and prints
`trials/unrecovered/p50/p95/max`. Exits 1 when p95 > `--threshold` (default 5 s), any episode never
reached `ready`, no episodes were found, or fewer than `--min-trials` were seen. Percentile is
nearest-rank.

```sh
ruby tools/reconnect-harness/run.rb [--threshold 5.0] [--min-trials 20] <log>...
ruby tools/reconnect-harness/test/reconnect_harness_test.rb
```

## Marker contract

A log line counts when it carries a timestamp and `TandemReconnect event=<disconnected|dead|ready>`:

- Android logcat (`adb logcat -v threadtime`): tag `TandemReconnect`, `MM-DD HH:MM:SS.mmm` stamp.
- macOS unified log (`log show`): `YYYY-MM-DD HH:MM:SS.ffffff+ZZZZ` stamp.

Markers carry no secrets or content. Android logcat is the primary source (both ends of an
episode on one clock); do not mix phone and Mac clocks in one episode.

## Scenario drivers (real hardware; run only per `docs/testing/manual-gates.md`)

- `scenario-wifi-switch.sh` — alternates phone Wi-Fi via `adb shell cmd wifi connect-network`.
- `scenario-mac-wake.sh` — `pmset schedule wake` + `pmset sleepnow` loop on the Mac.
- `scenario-force-idle.sh` — `dumpsys deviceidle force-idle` / `unforce` + screen-on.

Each saves the logcat and pipes it through `run.rb`.
