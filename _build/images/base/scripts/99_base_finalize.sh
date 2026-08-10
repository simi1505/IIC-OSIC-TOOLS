#!/bin/bash
# SPDX-FileCopyrightText: 2022-2026 Harald Pretl and Georg Zachl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC1091

set -e

# Create dirs if not yet existing
mkdir -p "$DESIGNS"
mkdir -p "$PDK_ROOT"
mkdir -p "$EXAMPLES"

# Folder for links to all tool binaries into one bin folder
mkdir -p "$TOOLS/bin"

# Create dir for logs
mkdir -p "$STARTUPDIR"/logs

# For the WSLg VGPU to correctly work, the potentially mounted driver directory needs to be added to the dynamic linker config:
echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf
ldconfig

# Set /usr/bin/python3 to provide "/usr/bin/python"
update-alternatives --set python /usr/bin/python3

# Update the mime-type and application database so typical IC-Design files are recognized
update-mime-database /usr/share/mime
update-desktop-database /usr/share/applications

# Note: XDG_RUNTIME_DIR is NOT created here. The XDG spec requires it to be
# owned by the current user with mode 0700, and the UID is only known at
# container startup; /etc/profile.d/iic-osic-tools-setup.sh creates a
# per-user /tmp/runtime-<uid> instead.

# Remove Ubuntu user in container to prevent conflicts with designer user
userdel ubuntu

# Trim the udisks2 GVfs volume monitor, which really is useless inside a
# container: there is no udisks daemon and no system D-Bus for it to talk to.
#
# Tumbler, the thumbnailer, is NOT trimmed with it. It was, and the result was
# an error dialog ("The thumbnailer-service can not be reached ... Install
# Tumbler") from Thunar and Ristretto every time a directory or an image was
# opened -- the applications ask for the service whether or not its activation
# file is there, and only the answer changes. Unlike the volume monitor,
# tumbler needs nothing but the session bus and works here: it activates and
# serves thumbnails in a VNC desktop and over X11 forwarding alike.
rm -f /usr/share/gvfs/remote-volume-monitors/udisks2.monitor \
      /usr/share/dbus-1/services/org.gtk.vfs.UDisks2VolumeMonitor.service

# Remove Rust toolchains/caches that rustup auto-downloads when pip has to
# build a package from source (no prebuilt wheel, e.g. on aarch64); a
# toolchain is re-downloaded on first cargo use if a user needs Rust
rm -rf "$HOME/.rustup" "$HOME/.cargo"

# Set access rights for home dir and designs dir
chown -R 1000:1000 "$HOME"
chmod -R +rw "$HOME"
chown -R 1000:1000 "$DESIGNS"

# Set correct user permissions
"$STARTUPDIR/scripts/set_user_permission.sh" "$STARTUPDIR" "$HOME"
