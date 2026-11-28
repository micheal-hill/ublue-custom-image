#!/usr/bin/bash
# Runs inside the container that `just build-live-iso` turns into the live USB's filesystem.
# The recipe starts it from stock Bazzite with /src (Bazzite's installer folder, our iso.yaml,
# trust-payload.sh, cosign.pub) and /info mounted, and these variables set: BASE_IMAGE,
# INSTALL_IMAGE_PAYLOAD, FLATPAK_DIR_SHORTNAME, PAYLOAD_VENDOR.
#
# A container rather than `podman build`: committing a ~25 GB layer briefly needs about three
# copies of it on disk, while Titanoboa only needs to read the files (the recipe mounts them).
set -euo pipefail

# Our signature policy first, so the `podman pull` in build.sh only accepts a payload signed
# with keys/cosign.pub
/src/trust-payload.sh "${PAYLOAD_VENDOR:?}" /src/cosign.pub
/src/build.sh

# What went in, for build-info.txt
jq -r --arg ref "${INSTALL_IMAGE_PAYLOAD}" '.[] | select((.names // []) | index($ref)) | .digest' \
	/var/lib/containers/storage/overlay-images/images.json >/info/payload-digest
flatpak list --system --columns=ref,version >/info/flatpaks
