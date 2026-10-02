# tools/fuzz/campaign (E71-01)

`run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir>` — chunked,
resumable 24 h fuzz campaign driver for the frame length-prefix parser. Writes
`<state-dir>/campaign-log.json` (duration, total execs, final corpus size, crash count) and exits 1
on a crash or hang. Driven by `.github/workflows/fuzz-campaign.yml`; contract and limits in
`tools/fuzz/README.md` (E71-01 section). Self-test: `test/run_campaign_test.sh`.
