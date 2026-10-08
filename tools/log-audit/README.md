tools/log-audit — E15-17: static scan of captured logs for content/secret strings.

## Contacts PII (E51-08)

`ruby tools/log-audit/test/contacts-pii_test.rb` — canary contact (`TANDEM-CANARY-<nonce>` in name,
number and email) audit contract on synthetic captures, plus a scan that the contacts sync sources
(Android `feature/contacts`, Mac `ContactsSyncClient` and contacts store) contain no logging call.

## Calls PII (E52-09)

`ruby tools/log-audit/test/calls-pii_test.rb` — canary caller (`TANDEM-CANARY-<nonce>` in name and
number) audit contract on synthetic captures, plus a scan that the call sources (Android
`feature/calls` and `CallsFeature`, Mac `FeatureCalls`) contain no logging call.
