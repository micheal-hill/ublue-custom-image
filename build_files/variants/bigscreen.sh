#!/bin/bash
# KDE Plasma Bigscreen as the "desktop mode" session of a Bazzite deck (HTPC)
# base: boots into Bigscreen, with Steam Gaming Mode one step away.
# GPU-agnostic: works on bazzite-deck and bazzite-deck-nvidia.

set -xeuo pipefail

SESSION=plasma-bigscreen-wayland.desktop

# Needs a deck base: SDDM autologin plus steamos-manager session switching
if ! command -v steamosctl || [[ ! -f /usr/share/steamos-manager/platform.toml ]]; then
	echo "The bigscreen variant needs a bazzite-deck* base (steamosctl / steamos-manager missing)" >&2
	exit 1
fi

# Install the Bigscreen build that matches the base's (versionlocked) Plasma.
PV=$(rpm -q --qf '%{VERSION}' plasma-workspace)
dnf5 -y install "plasma-bigscreen-${PV}" "plasma-bigscreen-wayland-${PV}" plasma-keyboard
for pkg in plasma-bigscreen plasma-bigscreen-wayland; do
	if [[ "$(rpm -q --qf '%{VERSION}' "${pkg}")" != "${PV}" ]]; then
		echo "${pkg} does not match plasma-workspace ${PV}" >&2
		exit 1
	fi
done
test -f "/usr/share/wayland-sessions/${SESSION}"

# Replace a literal string in a file. Fails the build if the text isn't there,
# so an upstream rewrite of a Bazzite script breaks CI instead of the TV box.
replace() {
	local - # keep the file contents out of the set -x trace
	set +x
	local file=$1 from=$2 to=$3 content
	echo "replace in ${file}: ${from} -> ${to}"
	content=$(<"${file}")
	if [[ "${content}" != *"${from}"* ]]; then
		echo "Expected text not found in ${file}: ${from}" >&2
		exit 1
	fi
	printf '%s\n' "${content//"${from}"/"${to}"}" >"${file}"
}

# Bazzite hard-codes Plasma Desktop as the deck "desktop mode" session:
# steamos-manager's default desktop session (Gaming Mode -> Switch to Desktop)
replace /usr/share/steamos-manager/platform.toml 'desktop = "plasma.desktop"' "desktop = \"${SESSION}\""
# the legacy session switcher the Steam client still calls
replace /usr/libexec/os-session-select 'desktop_session="plasma.desktop"' "desktop_session=\"${SESSION}\""
# boot-time autologin when /etc/bazzite/desktop_autologin exists (shipped in system_files/bigscreen)
replace /usr/libexec/bazzite-autologin 'SESSION="plasma.desktop"' "SESSION=\"${SESSION}\""

# Bigscreen's Steam tile goes to Gaming Mode instead of the desktop client
replace /usr/share/applications/steam.desktop 'Exec=/usr/bin/bazzite-steam %U' 'Exec=steamosctl switch-to-game-mode'
# Bigscreen ignores NoDisplay/Hidden, so drop launchers that don't belong on a TV
rm -f /usr/share/applications/opengamepadui.desktop
