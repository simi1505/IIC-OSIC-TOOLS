#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Harald Pretl and Georg Zachl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
"""Anchor the KLayout GUI DRC/LVS run directory to the layout file.

The IHP DRC and LVS menu macros build their output directory as a relative name
and expand it with a one-argument ``File.expand_path``, which resolves against
the working directory of the KLayout process. That directory is whatever the
caller happened to be in: with sak-open.py it is the folder of the clicked
layout, from a shell it is wherever the shell stood. The same layout therefore
writes its reports to a different place depending on how KLayout was started,
and the reports land next to the GDS instead of in the project's verification
folder.

Two changes per macro fix that:

1. A relative ``run_dir`` is resolved against the directory of the active layout
   file, so the result no longer depends on the working directory. Absolute
   values and ``~`` keep working unchanged, and so does the default when the
   option is left empty (it just becomes deterministic).
2. ``%top_cell%`` in ``run_dir`` is replaced by the name of the cell being run,
   sanitized for use as a path component. Without it the option is a fixed
   string, so every cell of a project shares one directory - which the DRC macro
   then deletes before each run.

Together they make a single setting such as

    ../verification/drc/%top_cell%.klayout.drc
    ../verification/lvs/%top_cell%.klayout.lvs

place the GUI results where sak-drc.sh and sak-lvs.sh already put the batch
ones, for every cell and from any working directory.

The matching option dialogs get their placeholder and tooltip updated, so the
new semantics are visible where the value is typed.

Both IHP PDKs ship their own copy of all four macros rather than symlinks, so
this runs once per PDK on the technology macro directory. Every rewrite is
idempotent, and a pattern that no longer matches is reported and skipped rather
than failing the build, so an upstream fix does not break the image.
"""

import sys
from pathlib import Path

# One entry per macro kind: the file name glob inside the macro directory, a
# label for the log, the text to find, and its replacement. Each `old` is a
# literal that occurs exactly once in the shipped macro, so a match is proof
# that the code is still the one this patch was written against.
PATCHES = (
    (
        "*_drc.lym",
        "DRC run directory",
        'run_dir = options[\'run_dir\']\n'
        'if run_dir.nil? || run_dir.strip.empty?\n'
        '  run_dir = "drc_run_#{top_cell}"\n'
        'end\n'
        'run_dir = File.expand_path(run_dir)\n',
        'run_dir = options[\'run_dir\']\n'
        'if run_dir.nil? || run_dir.strip.empty?\n'
        '  run_dir = "drc_run_#{top_cell}"\n'
        'end\n'
        '# A relative run_dir is resolved against the layout file, not against the\n'
        '# working directory KLayout was started in, and %top_cell% names the cell.\n'
        'run_dir_base = gds_path.to_s.empty? ? Dir.pwd : File.dirname(File.expand_path(gds_path.to_s))\n'
        'run_dir = run_dir.gsub(\'%top_cell%\', top_cell.to_s.gsub(/[^A-Za-z0-9_.-]/, \'_\'))\n'
        'run_dir = File.expand_path(run_dir, run_dir_base)\n',
    ),
    (
        "*_lvs.lym",
        "LVS run directory",
        'run_dir = options[\'run_dir\'].to_s.strip\n'
        'if run_dir.empty?\n'
        '  safe_top = top_cell.to_s.strip.empty? ? \'TOP\' : top_cell.gsub(/[^A-Za-z0-9_.-]/, \'_\')\n'
        '  timestamp = Time.now.strftime(\'%Y_%m_%d_%H_%M_%S\')\n'
        '  run_dir = File.expand_path("lvs_run_#{safe_top}_#{timestamp}")\n'
        'else\n'
        '  run_dir = File.expand_path(run_dir)\n'
        'end\n',
        'run_dir = options[\'run_dir\'].to_s.strip\n'
        '# A relative run_dir is resolved against the layout file, not against the\n'
        '# working directory KLayout was started in, and %top_cell% names the cell.\n'
        '# layout_path is nil when LVS runs on a given netlist without a layout.\n'
        'run_dir_base = layout_path.to_s.empty? ? Dir.pwd : File.dirname(File.expand_path(layout_path.to_s))\n'
        'safe_top = top_cell.to_s.strip.empty? ? \'TOP\' : top_cell.gsub(/[^A-Za-z0-9_.-]/, \'_\')\n'
        'if run_dir.empty?\n'
        '  timestamp = Time.now.strftime(\'%Y_%m_%d_%H_%M_%S\')\n'
        '  run_dir = File.expand_path("lvs_run_#{safe_top}_#{timestamp}", run_dir_base)\n'
        'else\n'
        '  run_dir = File.expand_path(run_dir.gsub(\'%top_cell%\', safe_top), run_dir_base)\n'
        'end\n',
    ),
    (
        "*_drc_options.lym",
        "DRC run directory hint",
        '    @dir_input.setPlaceholderText("Optional - default is ./drc_run_&lt;cell_name&gt;")\n',
        '    @dir_input.setPlaceholderText("Optional - default is drc_run_&lt;cell_name&gt; next to the layout")\n'
        '    @dir_input.setToolTip("Absolute, or relative to the directory of the layout file. '
        '%top_cell% is replaced by the cell name, so a single setting serves every cell, '
        'e.g. ../verification/drc/%top_cell%.klayout.drc")\n',
    ),
    (
        "*_lvs_options.lym",
        "LVS run directory hint",
        "    @widgets[:run_dir][:input].setToolTip(\n"
        "      'Output folder for LVS artifacts. Leave empty to auto-create a timestamped run directory.'\n"
        "    )\n",
        "    @widgets[:run_dir][:input].setToolTip(\n"
        "      'Output folder for LVS artifacts. Absolute, or relative to the directory of the '\\\n"
        "      'layout file. %top_cell% is replaced by the cell name, so a single setting serves '\\\n"
        "      'every cell, e.g. ../verification/lvs/%top_cell%.klayout.lvs. Leave empty to '\\\n"
        "      'auto-create a timestamped run directory next to the layout.'\n"
        "    )\n",
    ),
)


def patch(content: str, old: str, new: str):
    """Return `(content, state)`, where state is 'patched', 'present' or 'absent'."""
    if new in content:
        return content, "present"
    if old not in content:
        return content, "absent"
    return content.replace(old, new), "patched"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <klayout tech macros directory>", file=sys.stderr)
        return 2
    macro_dir = Path(sys.argv[1])
    if not macro_dir.is_dir():
        print(f"[WARN] KLayout macro directory not found at {macro_dir}")
        return 0

    for pattern, label, old, new in PATCHES:
        files = sorted(macro_dir.glob(pattern))
        if not files:
            print(f"[WARN] No {pattern} in {macro_dir}, {label} not patched")
            continue
        for fname in files:
            content = fname.read_text(encoding="utf-8")
            patched, state = patch(content, old, new)
            if state == "patched":
                fname.write_text(patched, encoding="utf-8")
                print(f"[INFO] Fixed the {label} in {fname}")
            elif state == "present":
                print(f"[INFO] The {label} in {fname} is already fixed")
            else:
                print(f"[WARN] {label} not patched in {fname} (already fixed upstream?)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
