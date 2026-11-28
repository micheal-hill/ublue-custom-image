#!/usr/bin/bash
# Make podman in the live system require our cosign signature for ghcr.io/<vendor>, before
# Bazzite's build.sh pulls the payload. This is the same policy build_files/common.sh puts in
# our images. Without it, stock Bazzite's policy accepts any image outside ghcr.io/ublue-os.
#
# Usage: trust-payload.sh <vendor> <path to cosign.pub>
set -euo pipefail

vendor=${1:?vendor (GitHub owner) required}
pubkey=${2:?path to cosign.pub required}
[[ -s "${pubkey}" ]] || {
	echo "No public key at ${pubkey}" >&2
	exit 1
}

key="/etc/pki/containers/${vendor}.pub"
scope="ghcr.io/${vendor}"
install -Dm0644 "${pubkey}" "${key}"

policy_file=/etc/containers/policy.json
policy=$(jq --arg scope "${scope}" --arg key "${key}" \
	'.transports.docker[$scope] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
	"${policy_file}")
printf '%s\n' "${policy}" >"${policy_file}"

mkdir -p /etc/containers/registries.d
cat >"/etc/containers/registries.d/${vendor}.yaml" <<EOF
docker:
  ${scope}:
    use-sigstore-attachments: true
EOF

echo "Payloads from ${scope} must now be signed with ${pubkey}"
