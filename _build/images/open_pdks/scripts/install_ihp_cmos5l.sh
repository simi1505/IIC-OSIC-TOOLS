#!/bin/bash
# SPDX-FileCopyrightText: 2026 Harald Pretl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
set -e
set -o pipefail
export SCRIPT_DIR=$TOOLS/osic-multitool
PDK_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd /tmp || exit 1

if [ ! -d "$PDK_ROOT" ]; then
    mkdir -p "$PDK_ROOT"
fi

# CMOS5L has symlinks to SG13G2 (OSDI models, Xyce plugins, xschem libs)
if [ ! -d "$PDK_ROOT/ihp-sg13g2" ]; then
    echo "[ERROR] IHP SG13G2 PDK not found at $PDK_ROOT/ihp-sg13g2."
    echo "[ERROR] Please install SG13G2 first, as CMOS5L depends on it."
    exit 1
fi

# Install IHP-SG13CMOS5L
PDK="ihp-sg13cmos5l"
IHP_CMOS5L_REPO_URL="https://github.com/iic-jku/ihp-sg13cmos5l.git"

echo "[INFO] Installing IHP SG13CMOS5L PDK."
git clone "$IHP_CMOS5L_REPO_URL" ihp-cmos5l
cd ihp-cmos5l || exit 1

# Store git hash of installed PDK version for reference
PDK_COMMIT=$(git rev-parse HEAD)

# Now move to the proper location
cd /tmp || exit 1
if [ -d ihp-cmos5l ]; then
	mv ihp-cmos5l "$PDK_ROOT/$PDK"
else
	echo "[ERROR] PDK directory 'ihp-cmos5l' not found after clone!"
	exit 1
fi

# Store git hash
echo "$PDK_COMMIT" > "${PDK_ROOT}/${PDK}/COMMIT"

# Reconcile the repo-level versions.txt used by the KLayout DRC/LVS version check.
# run_drc.py resolves it as <PDK_ROOT>/versions.txt (Path(__file__).parents[5]),
# so one file has to serve both PDKs. install_ihp.sh already installed SG13G2's
# copy, which carries entries for every tool; CMOS5L ships its own declaring only
# a KLayout minimum. Keep SG13G2's file and raise just the klayout line to the
# stricter of the two, so neither PDK's gate is silently weakened when they drift.
SHARED_VERSIONS="$PDK_ROOT/versions.txt"
CMOS5L_VERSIONS="$PDK_ROOT/$PDK/versions.txt"
if [ -f "$SHARED_VERSIONS" ] && [ -f "$CMOS5L_VERSIONS" ]; then
	python3 - "$SHARED_VERSIONS" "$CMOS5L_VERSIONS" << 'PYEOF'
import re
import sys

def klayout_version(path):
    with open(path, 'r') as f:
        for line in f:
            match = re.match(r'\s*klayout\s+(\S+)', line)
            if match:
                return match.group(1)
    return None

def sort_key(version):
    return tuple(int(part) for part in re.findall(r'\d+', version))

shared_path, own_path = sys.argv[1], sys.argv[2]
shared, own = klayout_version(shared_path), klayout_version(own_path)

if shared is None or own is None:
    print(f"[WARN] klayout entry missing (shared={shared}, cmos5l={own}), "
          f"leaving {shared_path} untouched")
    sys.exit(0)
if sort_key(own) <= sort_key(shared):
    print(f"[INFO] {shared_path} already requires klayout {shared} >= {own}")
    sys.exit(0)

with open(shared_path, 'r') as f:
    content = f.read()
content = re.sub(r'(?m)^(\s*klayout\s+)\S+', lambda m: m.group(1) + own, content, count=1)
with open(shared_path, 'w') as f:
    f.write(content)
print(f"[INFO] Raised klayout requirement in {shared_path} from {shared} to {own}")
PYEOF
else
	echo "[WARN] versions.txt not found (shared: $SHARED_VERSIONS, CMOS5L: $CMOS5L_VERSIONS)."
	echo "[WARN] The KLayout DRC/LVS version check may use the wrong minimum."
fi

# Remove .git directory to save space
rm -rf "$PDK_ROOT/$PDK/.git"

# Add custom bindkeys for Magic
echo "# Custom bindkeys for ICD" 		        >> "$PDK_ROOT/$PDK/libs.tech/magic/$PDK.magicrc"
echo "source $SCRIPT_DIR/iic-magic-bindkeys" 	>> "$PDK_ROOT/$PDK/libs.tech/magic/$PDK.magicrc"

# Fix KLayout netlist import templates (make m= optional, accept nf= for ng=).
# CMOS5L ships its own copy of ihp130_pcell_templates.py rather than a symlink
# into SG13G2, so install_ihp.sh's patch does not reach it and it has to be
# applied here too. Shared helper, same fix for both PDKs.
echo "[INFO] Fixing KLayout netlist import templates."
TEMPLATES_FILE="$PDK_ROOT/$PDK/libs.tech/klayout/python/import_netlist/ihp130_pcell_templates.py"
if [ -f "$TEMPLATES_FILE" ]; then
	python3 "$PDK_SCRIPT_DIR/fix_netlist_templates.py" "$TEMPLATES_FILE"
else
	echo "[WARN] KLayout netlist import templates not found at $TEMPLATES_FILE"
fi

# Make the PCell preprocessor temp file per-process. CMOS5L ships its own copy of
# the PCell library __init__.py (it only symlinks pycell4klayout-api and
# pypreprocessor into SG13G2), so install_ihp.sh's patch does not reach it.
# Both PDKs use the same PCell module names, so without this two concurrent
# KLayout processes delete each other's /tmp/<module>_pre.py and the loser
# registers no PCells at all. Shared helper, same fix for both PDKs.
echo "[INFO] Making the PCell preprocessor temp file per-process."
PYCELL_INIT="$PDK_ROOT/$PDK/libs.tech/klayout/python/sg13cmos5l_pycell_lib/__init__.py"
if [ -f "$PYCELL_INIT" ]; then
	python3 "$PDK_SCRIPT_DIR/fix_pycell_tempfile.py" "$PYCELL_INIT"
else
	echo "[WARN] KLayout PCell library not found at $PYCELL_INIT"
fi

# Remove testing folders to save space
echo "[INFO] Removing unnecessary files to save space."
cd "$PDK_ROOT/$PDK"
find . -name "testing" -print0 | xargs -0 rm -rf

# Remove *.orig files created during PDK preparation
find "$PDK_ROOT/$PDK/libs.tech/xschem" -name "*.orig" -delete

# Add missing symlinks from CMOS5L pycell_lib to SG13G2 pycell_lib
# The CMOS5L PDK uses symlinks to SG13G2 PCell code (e.g. nmos_code.py),
# but some new dependencies (device_base_code.py, guard_ring_code.py) added
# upstream in SG13G2 are not yet symlinked in the CMOS5L repo.
CMOS5L_IHP="$PDK_ROOT/$PDK/libs.tech/klayout/python/sg13cmos5l_pycell_lib/ihp"
SG13G2_IHP="../../../../../../ihp-sg13g2/libs.tech/klayout/python/sg13g2_pycell_lib/ihp"
for pyfile in device_base_code.py guard_ring_code.py; do
    if [ ! -e "$CMOS5L_IHP/$pyfile" ] && [ -e "$PDK_ROOT/ihp-sg13g2/libs.tech/klayout/python/sg13g2_pycell_lib/ihp/$pyfile" ]; then
        ln -s "$SG13G2_IHP/$pyfile" "$CMOS5L_IHP/$pyfile"
        echo "[INFO] Created missing symlink: $pyfile"
    fi
done

# Rebuild the CMOS5L-own Verilog-A models for ngspice, the same way
# install_ihp.sh does for SG13G2: in-image and with --compile-model-generic, so
# the resulting OSDI runs on any host CPU. The PDK repo ships a prebuilt
# cap_cmomi.osdi, but it comes from whoever committed it (unknown OpenVAF version
# and target CPU), so it is not trustworthy for the image. psp103 and r3_cmc are
# symlinks into SG13G2 and are already compiled by install_ihp.sh.
# NOTE: this is the ngspice copy in libs.tech/ngspice/osdi. The VACASK copies in
# libs.tech/vacask/osdi are built separately further down.
echo "[INFO] Compiling Verilog-A models."
export PATH="$TOOLS/openvaf/bin:$PATH"
# Drop the prebuilt object first: openvaf-compile-va.sh does not set -e, so
# without this the check below would happily pass on the stale shipped file.
rm -f "$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/cap_cmomi.osdi"
cd "$PDK_ROOT/$PDK/libs.tech/verilog-a" || exit 1
chmod +x openvaf-compile-va.sh
./openvaf-compile-va.sh --compile-model-generic
if [ ! -f "$PDK_ROOT/$PDK/libs.tech/ngspice/osdi/cap_cmomi.osdi" ]; then
	echo "[ERROR] OpenVAF model compilation for ngspice failed!"
	exit 1
fi

# Perform required preparation of IHP CMOS5L PDK for use with VACASK.
# Upstream's sg13cmos5ltovc.py does all of it (requested as
# https://codeberg.org/arpadbuermen/VACASK/issues/94): it converts the ngspice
# models, compiles cap_cmomi.va to OSDI, symlinks in the SG13G2 OSDI objects,
# writes .vacaskrc.toml and patches the xschem symbols and xschemrc.
# Needs VACASK >= b9ca96e, which keeps the conversion of the models CMOS5L
# symlinks from SG13G2 inside the CMOS5L tree and makes cap_cmomi's feed
# default a literal, so it stays overridable (regression test 29).
echo "[INFO] Preparing IHP CMOS5L PDK for VACASK."
cd /tmp || exit 1
rm -rf "${VACASK_NAME}"

if [ -z "${VACASK_REPO_COMMIT:-}" ]; then
	# No specific ref -> shallow clone the default branch for speed
	git clone --filter=blob:none --depth 1 "${VACASK_REPO_URL}" "${VACASK_NAME}"
	cd "${VACASK_NAME}" || exit 1
else
	# When a specific ref (branch, tag, or commit) is given try a shallow fetch of that ref.
	# Use --no-checkout so we can fetch a single ref shallowly without downloading history.
	git clone --filter=blob:none --no-checkout "${VACASK_REPO_URL}" "${VACASK_NAME}"
	cd "${VACASK_NAME}" || exit 1

	# Try to fetch the exact ref shallowly. This usually works for branches and tags and
	# for commit SHAs on servers that allow fetching by SHA with depth.
	if git fetch --depth 1 origin "${VACASK_REPO_COMMIT}" >/dev/null 2>&1; then
		git checkout FETCH_HEAD
	else
		# Fallback: fetch all refs and tags, then checkout the requested ref (slower but reliable)
		git fetch --all --tags --prune
		git checkout "${VACASK_REPO_COMMIT}"
	fi
fi
cd /tmp || exit 1

OPENVAF_DIR=${TOOLS}/openvaf/bin PYTHONPATH=/tmp/${VACASK_NAME}/python \
    PDK_ROOT="$PDK_ROOT" PDK="$PDK" \
    python3 -m sg13cmos5ltovc --openvaf-options --target_cpu generic

# ---------------------------------------------------------------------------
# Add the diode and PNP corners to the "Add VACASK models symbol" menu entry.
#
# The corner list upstream ships covers MOSlv, MOShv, RES and CAP only, so a
# design using a diode or the pnpMPA gets no corner section for it and has to
# add the include by hand. CMOS5L converts both corner files, so list them.
# Upstream omits cornerDIO for SG13G2 as well, i.e. this is a local addition
# and not a fix -- keep it as a separate, clearly bounded edit.
# ---------------------------------------------------------------------------
echo "[INFO] Adding the diode and PNP corners to the xschem VACASK menu."
python3 - "$PDK_ROOT" "$PDK" << 'PYEOF'
import os
import sys

pdkroot, pdk = sys.argv[1], sys.argv[2]
path = os.path.join(pdkroot, pdk, "libs.tech", "xschem", "xschem-vacask")

with open(path) as f:
    tcl = f.read()

anchor = 'include \\"cornerCAP.lib\\" section=cap_typ\n'
added = ('include \\"cornerDIO.lib\\" section=dio_tt\n'
         'include \\"cornerPNP.lib\\" section=typ\n')

if 'cornerDIO.lib' in tcl and 'cornerPNP.lib' in tcl:
    print("[INFO] Diode and PNP corners already listed, nothing to do.")
elif anchor not in tcl:
    print("[WARN] cornerCAP.lib entry not found in %s, corner list left as is "
          "(upstream changed the menu?)" % path)
else:
    with open(path, "w") as f:
        f.write(tcl.replace(anchor, anchor + added, 1))
    print("[INFO] Added cornerDIO.lib and cornerPNP.lib to the corner list.")
PYEOF

# Drop the backups the converter leaves behind: xschemrc.orig from its own
# xschemrc patcher and *.sym.orig from xschem2vc's symbol patcher.
find "$PDK_ROOT/$PDK/libs.tech/xschem" -name "*.orig" -delete
if [ -d "$PDK_ROOT/$PDK/libs.ref/sg13cmos5l_stdcell/sym" ]; then
	find "$PDK_ROOT/$PDK/libs.ref/sg13cmos5l_stdcell/sym" -name "*.orig" -delete
fi

rm -rf "/tmp/${VACASK_NAME}"

# gzip Liberty (.lib) files. The SRAM Liberty files are symlinks into the
# SG13G2 PDK and are already compressed by install_ihp.sh.
bash "$PDK_SCRIPT_DIR/gzip_liberty.sh" "$PDK_ROOT/$PDK"

# CMOS5L is largely symlinks into SG13G2, so a rename on the SG13G2 side silently
# leaves a broken link behind. Report them instead of failing the build, 
# since a dangling link is a PDK-side fix and not every one of them blocks the tools.
echo "[INFO] Checking for broken symlinks into SG13G2."
BROKEN_LINKS=$(find "$PDK_ROOT/$PDK" -xtype l || true)
if [ -n "$BROKEN_LINKS" ]; then
	echo "[WARN] Broken symlinks found in $PDK:"
	echo "$BROKEN_LINKS" | sed 's/^/[WARN]   /'
else
	echo "[INFO] No broken symlinks found."
fi

echo "[INFO] IHP SG13CMOS5L PDK installation complete."
