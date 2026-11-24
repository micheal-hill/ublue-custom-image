#!/bin/bash
# Nix (multi-user daemon) from Fedora's own packages, for user environments
# (home-manager, devenv, nix-direnv). Independent of the variant: add "nix" to
# an image's "features" in images.json.
#
# bootc keeps / read-only, so /nix is a bind mount of /var/nix
# (system_files/features/nix/usr/lib/systemd/system/nix.mount). The /nix
# directories that the nix-system RPM puts in the image only serve as the
# mount point.

set -xeuo pipefail

dnf5 -y install nix nix-daemon

# Fedora's nix.conf already enables nix-command and flakes. Let wheel users
# (admins, who have sudo anyway) add binary caches such as devenv's or a
# flake's nixConfig substituters.
grep -q '^trusted-users' /etc/nix/nix.conf || printf '%s\n' \
	'' \
	'# Added by this image: admins may use extra substituters (devenv, flake nixConfig)' \
	'trusted-users = root @wheel' >>/etc/nix/nix.conf

# Fedora's SELinux policy has no rules for /nix, so everything there is
# default_t, and systemd can't create the daemon socket in it (seen in a VM:
# nix-daemon.socket never listened). Label the store like /usr, Nix's state
# like /var and the socket directory like /run, and give /var/nix (the
# bind-mount source) the same labels as /nix. One import = one policy rebuild.
semanage import <<'EOF'
fcontext -a -e /nix /var/nix
fcontext -a -t usr_t '/nix(/.*)?'
fcontext -a -t var_t '/nix/var(/.*)?'
fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
EOF
[[ "$(matchpathcon -n /nix/store)" == *:usr_t:* ]]
[[ "$(matchpathcon -n /nix/var/nix/daemon-socket)" == *:var_run_t:* ]]
[[ "$(matchpathcon -n /var/nix/var/nix/daemon-socket)" == *:var_run_t:* ]]

systemctl enable nix.mount nix-daemon.socket

# The units this feature relies on must exist and parse
test -d /nix/store
for unit in nix.mount nix-store-dir.service nix-daemon.socket nix-daemon.service; do
	test -f "/usr/lib/systemd/system/${unit}"
done
systemd-analyze verify --man=no /usr/lib/systemd/system/nix.mount /usr/lib/systemd/system/nix-store-dir.service
