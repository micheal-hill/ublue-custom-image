#!/bin/bash
# Entry point run by the Containerfile. Applies the shared layer, then the
# variant named by the VARIANT build arg, then each optional feature in
# FEATURES. Variants never branch on GPU: the base image chosen in images.json
# decides that.

set -xeuo pipefail

: "${VARIANT:?VARIANT build arg is required (see images.json)}"
: "${IMAGE_NAME:?IMAGE_NAME build arg is required}"
: "${IMAGE_VENDOR:=localhost}"
: "${FEATURES:=}"
export VARIANT IMAGE_NAME IMAGE_VENDOR

if [[ ! -f "/ctx/variants/${VARIANT}.sh" ]]; then
	echo "Unknown variant '${VARIANT}': no build_files/variants/${VARIANT}.sh" >&2
	exit 1
fi
read -ra features <<<"${FEATURES}"
for feature in "${features[@]}"; do
	if [[ ! -f "/ctx/features/${feature}.sh" ]]; then
		echo "Unknown feature '${feature}': no build_files/features/${feature}.sh" >&2
		exit 1
	fi
done

# Overlay system_files/shared/, system_files/<variant>/ and system_files/features/<feature>/
# onto the image. This happens before any package is installed: RPM keeps an existing file
# at a %config path and writes its own version as .rpmnew, which the scripts then remove.
layers=(shared "${VARIANT}")
for feature in "${features[@]}"; do
	layers+=("features/${feature}")
done
for layer in "${layers[@]}"; do
	if [[ -d "/ctx/system_files/${layer}" ]]; then
		cp -avf "/ctx/system_files/${layer}/." /
	fi
done

/ctx/common.sh
"/ctx/variants/${VARIANT}.sh"
for feature in "${features[@]}"; do
	"/ctx/features/${feature}.sh"
done

# Leave /run and /var empty: bootc only applies /var at install time, and
# `bootc container lint` flags leftovers from dnf and systemd-analyze
rm -rf /run/dnf /run/systemd/systemd-units-load /var/lib/dnf
