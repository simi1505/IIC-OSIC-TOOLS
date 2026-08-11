# Test 31: open-pdks regression tests with ihp-sg13cmos5l

`test_drc_lvs_pex_sg13cmos5l.sh` runs the DRC / LVS / PEX regression suite of
[open-pdks-regression-tests](https://github.com/iic-jku/open-pdks-regression-tests)
against the `ihp-sg13cmos5l` PDK of the image. It is the sibling of test 26,
which does the same for `ihp-sg13g2`.

The test:

- clones the `main` branch of the regression repository (shallow, incl.
  submodules) into the run dir and marks it a `safe.directory`, since the
  container user is usually not the owner of the checkout;
- switches to the PDK with `source sak-pdk-script.sh ihp-sg13cmos5l sg13cmos5l_stdcell`;
- runs `make regression` in `ihp-sg13cmos5l/`, which iterates over **every**
  `.gds` in `layout/` (26 cells at the time of writing) and runs, per cell:
  KLayout DRC, KLayout LVS (schematic netlist exported from Xschem), Magic DRC,
  Magic + Netgen LVS, and Magic PEX in all three modes (`EXT_MODE=1/2/3`).
  KPEX is currently commented out in the regression target upstream;
- passes when the Makefile's regression summary reports no unexpected failure.

The cell inventory covers the LV and HV device flavors (`nmos`/`pmos` as tap,
ring-device and ring-PCell variants, RF MOS), the passives (`rhigh`, `rppd`,
`rsil`, MOM caps), the antenna diodes, and `sg13_combined` as a multi-device
cell.

Only the verdict goes to the console; the clone output and the full
`make regression` transcript are in
`$IIC_TEST_RUNDIR/<run-id>/31/drc_lvs_pex_sg13cmos5l.log` (default
`/tmp/iic-osic-tools-tests/...`, see [../TESTS.md](../TESTS.md)). Set `DEBUG=1`
for progress messages while debugging.

## Known failures

The regression target tolerates a pinned `KNOWN_FAILS` list (defined in the
regression repo's `ihp-sg13cmos5l/Makefile`, one entry per cell or
`<cell>:<tool>`); they are reported as `KNOWN FAIL (ignored)` and do not fail
the test, while any *other* failure does. A pinned failure that starts passing
is therefore not flagged as a failure here; it only shows up in the regression
summary in the log.

The baseline itself is deliberately **not** duplicated here: it is maintained in
the regression repository next to the `KNOWN_FAILS` variable it documents, see
`ihp-sg13cmos5l/KNOWN_ISSUES.md` (what is pinned and why) and
`ihp-sg13cmos5l/FINDINGS.md` (PDK quirks and work-arounds) there.

## Differences to test 26

The script is a straight port of `26/test_drc_lvs_pex_sg13g2.sh`; the only
differences are the PDK name, the standard cell library, the subdirectory of the
regression repo, and the log/run-dir names. Everything PDK-specific (cell list,
`KNOWN_FAILS`) lives in the regression repository, not here.

Consequently the two tests do not have to stay in sync beyond the mechanics: a
PDK difference that changes the outcome (`ihp-sg13cmos5l` has no `DigiSub` and no
`NBULAY`, for instance) is handled in the regression repository, and this test
just reports the verdict.
