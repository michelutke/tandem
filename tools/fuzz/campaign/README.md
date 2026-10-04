# tools/fuzz/campaign (E71-01, E71-02)

`run_campaign.sh <jazzer|libfuzzer> <total-seconds> <segment-seconds> <state-dir> [frame|envelope|qr]` — chunked,
resumable 24 h fuzz campaign driver for the frame length-prefix parser (`frame`, default, E71-01) or the Envelope protobuf decoder (`envelope`, E71-02). Writes
`<state-dir>/campaign-log.json` (duration, total execs, final corpus size, crash count) and exits 1
on a crash or hang. Driven by `.github/workflows/fuzz-campaign.yml`; contract and limits in
`tools/fuzz/README.md` (E71-01 section). Self-test: `test/run_campaign_test.sh`.

E71-03 adds `qr`: the Android QR pairing payload parser (`QrPayloadFuzzTest` in `:core:pairing`, run via `JAZZER_MODULE=core:pairing`). Jazzer only; macOS never parses QR, so `libfuzzer qr` exits 2.

E71-04 / E71-13 add `domain`: the per-proto-file message decoders (Jazzer `DomainDecoderFuzzTest` in `:core:protocol`, libFuzzer on Swift). `MESSAGE=<proto file stem>` picks the decoder (`MESSAGE=media_control run_campaign.sh libfuzzer ... domain`); `campaign-log.json` records it as `message`.
