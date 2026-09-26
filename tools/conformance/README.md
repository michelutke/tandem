tools/conformance — E15-01, E15-02, E15-03: runs protocol/vectors against both the Kotlin and Swift codecs.

`run.sh` (`run.rb`) runs the Android conformance runner (`android/core/pairing`'s
`ConformanceRunnerTest`, E15-01) and the macOS conformance runner
(`macos/Packages/TandemProtocol`'s `ConformanceRunnerTests`, E15-02), each of which loads every
manifest under `protocol/vectors/`, dispatches by category through an explicit table (an
undeclared category is an error, never a silent skip), and writes its own per-vector JSON report
to `tools/conformance/reports/<platform>-report.json`. `run.rb` merges both reports into
`tools/conformance/reports/report.json`, prints `<platform>:<vector id>` for every failing vector,
and exits non-zero if either platform's command fails to run or any vector fails.

Self-test: `ruby tools/conformance/test/run_test.rb` (stubs both platform commands so it runs
without Gradle/swift test).

Not yet wired into CI as a required check (E15-03); see `CLAUDE.md`.
