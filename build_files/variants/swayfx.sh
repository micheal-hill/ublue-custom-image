#!/bin/bash
# SwayFX + Noctalia desktop as an extra login session next to KDE Plasma, which
# stays as the fallback session. GPU-agnostic: works on any Bazzite KDE desktop base.

set -xeuo pipefail

# Plasma Login Manager (Bazzite KDE desktop images) lists every session in
# /usr/share/wayland-sessions, so SwayFX just needs to be installed.
if ! rpm -q plasma-workspace plasma-login-manager; then
	echo "The swayfx variant expects a Bazzite KDE desktop base (e.g. bazzite, bazzite-nvidia)" >&2
	exit 1
fi

# One transaction: swayfx Provides/Conflicts "sway", so sway-config-fedora's
# "sway >= 1.8" must resolve to swayfx here. Terra (disabled in the shipped
# image) is enabled for this transaction only and limited to the packages named
# in includepkgs, so it can't replace anything else.
#   - noctalia (Fedora): the shell, replacing waybar, mako, rofi, swayidle and the tray applets
#   - ghostty (Terra) is the terminal; fuzzel is a fallback launcher
#   - nwg-displays (Terra): screen resolution and layout, since KDE's display settings
#     can't drive sway
#   - KDE's own apps (Dolphin, Konsole, Bluetooth and audio settings, polkit agent)
#     cover the rest, so blueman, pavucontrol, foot and a second file manager aren't added
#   - fonts named by the default configs (Bazzite skips weak deps, so list them).
#     The theme is Breeze in both sessions, set in KDE System Settings.
dnf5 -y install \
	--enablerepo=terra \
	--setopt=terra.includepkgs='swayfx,ghostty,ghostty-*,nwg-displays,jetbrainsmono-nerd-fonts,firacode-nerd-fonts,hack-nerd-fonts' \
	swayfx sway-config-fedora sway-systemd \
	noctalia \
	xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
	ghostty ghostty-terminfo ghostty-shell-integration fuzzel nwg-displays \
	grim slurp wl-clipboard \
	neovim \
	rsms-inter-vf-fonts google-roboto-fonts \
	jetbrainsmono-nerd-fonts firacode-nerd-fonts hack-nerd-fonts

rpm -q swayfx noctalia ghostty nwg-displays
if rpm -q sway; then
	echo "Stock sway got installed instead of swayfx" >&2
	exit 1
fi

# Our /etc/sway/config and /etc/sway/environment (copied in before the install) are
# kept by RPM, which drops Fedora's versions next to them as .rpmnew. Check ours won,
# then remove those copies.
grep -q 'exec noctalia' /etc/sway/config
grep -q 'WLR_NO_HARDWARE_CURSORS=1$' /etc/sway/environment
rm -f /etc/sway/config.rpmnew /etc/sway/environment.rpmnew

# nwg-displays only works under wlroots-style compositors: hide it in Plasma's menus.
# It also exits unless ~/.config/sway exists, which user-tmpfiles.d/sway-config-dir.conf
# creates at login.
test -f /usr/share/user-tmpfiles.d/sway-config-dir.conf
DISPLAYS_FILE=/usr/share/applications/nwg-displays.desktop
sed -i '/^\[Desktop Entry\]$/a OnlyShowIn=sway;' "${DISPLAYS_FILE}"
grep -qx 'OnlyShowIn=sway;' "${DISPLAYS_FILE}"

# In a VM, resize the screen to follow the viewer window (the unit skips itself on hardware)
test -x /usr/libexec/sway-vm-autoresize
systemctl --global enable sway-vm-autoresize.service

# Show "SwayFX" at the login screen (the session file comes from sway-config-fedora)
SESSION_FILE=/usr/share/wayland-sessions/sway.desktop
test -f "${SESSION_FILE}"
sed -i 's/^Name=Sway$/Name=SwayFX/' "${SESSION_FILE}"

# Make SwayFX the login screen's default session. Plasma Login Manager's greeter
# preselects [Greeter] PreselectedSession (a session file name) for users who
# have no remembered session; after that it remembers each user's last choice.
# System Settings > Login Screen writes /etc/plasmalogin.conf, which overrides this.
PLM_DEFAULTS=/usr/lib/plasmalogin/defaults.conf
grep -qx '\[Greeter\]' "${PLM_DEFAULTS}"
sed -i '/^\[Greeter\]$/a PreselectedSession=sway.desktop' "${PLM_DEFAULTS}"
grep -qx 'PreselectedSession=sway.desktop' "${PLM_DEFAULTS}"

# KWallet unlock under sway: /etc/sway/config runs this directly
test -x /usr/libexec/pam_kwallet_init

# Defaults referenced by system_files must exist
test -f /usr/share/applications/org.kde.dolphin.desktop
test -f /usr/share/applications/org.kde.konsole.desktop
test -x /usr/libexec/kf6/polkit-kde-authentication-agent-1
test -f /etc/xdg/menus/applications.menu
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/xdg-desktop-portal/portals/kwallet.portal
ghostty +validate-config --config-file=/etc/skel/.config/ghostty/config.ghostty
[[ -n "$(fc-list 'FiraCode Nerd Font Mono')" ]]
