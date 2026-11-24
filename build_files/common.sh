#!/bin/bash
# Shared layer applied to every image: image identity and signature policy.

set -xeuo pipefail

# --- Image identity ---------------------------------------------------------
# Bazzite's tooling (ujust, brh rebase helpers) reads image-info.json. Point it
# at this image, but keep "base-image-name" (kinoite) so Bazzite's KDE-specific
# branches keep working.
IMAGE_INFO=/usr/share/ublue-os/image-info.json
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"
info=$(jq --arg name "${IMAGE_NAME}" --arg vendor "${IMAGE_VENDOR}" --arg ref "${IMAGE_REF}" \
	'."image-name" = $name | ."image-vendor" = $vendor | ."image-ref" = $ref' "${IMAGE_INFO}")
printf '%s\n' "${info}" >"${IMAGE_INFO}"

# --- Signature policy -------------------------------------------------------
# Only once a cosign key exists (keys/cosign.pub) and the image is published
# under a real GitHub owner. Local test builds skip this.
if [[ -f /ctx/keys/cosign.pub && "${IMAGE_VENDOR}" != "localhost" ]]; then
	KEY="/etc/pki/containers/${IMAGE_VENDOR}.pub"
	SCOPE="ghcr.io/${IMAGE_VENDOR}"
	install -Dm0644 /ctx/keys/cosign.pub "${KEY}"

	POLICY=/etc/containers/policy.json
	policy=$(jq --arg scope "${SCOPE}" --arg key "${KEY}" \
		'.transports.docker[$scope] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
		"${POLICY}")
	printf '%s\n' "${policy}" >"${POLICY}"

	mkdir -p /etc/containers/registries.d
	cat >"/etc/containers/registries.d/${IMAGE_VENDOR}.yaml" <<EOT
docker:
  ${SCOPE}:
    use-sigstore-attachments: true
EOT
else
	echo "Signing policy skipped (no keys/cosign.pub or local-only vendor '${IMAGE_VENDOR}')"
fi
