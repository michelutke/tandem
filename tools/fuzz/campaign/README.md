# tools/fuzz/campaign (E71-01, E71-02)

`run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir> [frame|envelope]` — chunked,
resumable 24 h fuzz campaign driver for the frame length-prefix parser (`frame`, default, E71-01) or the Envelope protobuf decoder (`envelope`, E71-02). Writes
`<state-dir>/campaign-log.json` (duration, total execs, final corpus size, crash count) and exits 1
on a crash or hang. Driven by `.github/workflows/fuzz-campaign.yml`; contract and limits in
`tools/fuzz/README.md` (E71-01 section). Self-test: `test/run_campaign_test.sh`.
