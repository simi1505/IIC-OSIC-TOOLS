# Test 34: KLayout GUI DRC/LVS run directory

`test_klayout_run_dir.sh` checks the run-directory fix that `install_ihp.sh` and `install_ihp_cmos5l.sh` apply to the KLayout DRC and LVS menu macros of both IHP PDKs (`fix_klayout_run_dir.py`).

The IHP macros build their output directory as a relative name and expand it against the working directory of the KLayout process, so the same layout writes its reports somewhere else depending on how KLayout was started. The fix resolves a relative run directory against the layout file instead, and replaces `%top_cell%` in it with the cell name, so one setting in the options dialog such as `../verification/drc/%top_cell%.klayout.drc` serves every cell of a project.

That fix is applied by matching the shipped macro text. A PDK bump that rewrites those lines makes it skip with a `[WARN]` in the build log, which is easy to miss, so this test is the alarm. Per PDK and for DRC and LVS it checks:

- the installed macro resolves its run directory against the layout file
- the installed macro substitutes `%top_cell%`
- no one-argument `File.expand_path(run_dir)` is left, which is what resolved against the working directory
- the options dialog documents `%top_cell%`, so the placeholder is discoverable where the value is typed
- macro and options dialog are still well-formed XML and still parse as Ruby, which is what a bad patch would break

It closes with the resolution itself, run from a working directory unrelated to the layout: a relative run directory follows the layout, an absolute one is left alone, the default lands next to the layout, no layout falls back to the working directory, and a cell name with a slash is sanitized into a single path component.

The test needs no display and runs no DRC, so it finishes in seconds. It reports only its verdict on the console, the per-case `[PASS]`/`[FAIL]` results and the full command output go into the log. Set `SAK_TEST_VERBOSE=1` to get every case on the console while debugging a regression.

Set `PDK_ROOT=<path>` to check a PDK tree other than the installed one.
