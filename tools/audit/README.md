tools/audit — E15-18: discovers and runs tools/<tool>/audit-step.sh by convention, writing one pass/fail/pending report.

`--expected <file>` (E15-23 Phase 1 gate): `tools/audit/expected-steps.txt` lists one tool directory name per line
(`#` comments allowed). A listed step with no `tools/<name>/audit-step.sh` fails the run, naming the step. Later phases
append to the file. `run.sh --subset ci --expected tools/audit/expected-steps.txt` is what `.github/workflows/audit.yml` runs.
