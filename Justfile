set dotenv-filename := "image-template.env"
set dotenv-load

export repo_organization := env_var("REPO_ORGANIZATION")
export repo_name := env_var("REPO_NAME")
export image_keywords := env_var("IMAGE_KEYWORDS")
export image_logo_url := env_var("IMAGE_LOGO_URL")
export default_tag := env_var("DEFAULT_TAG")
export bib_image := env_var("BIB_IMAGE")

# The rechunker (https://github.com/coreos/chunkah), pinned by digest. To update it, pick a
# release and take its digest from https://quay.io/repository/coreos/chunkah?tab=tags
chunkah_image := "quay.io/coreos/chunkah:v0.7.1@sha256:71e593421c5de7dcc7c8c5c50e98d3bac572055a76f399f61a491d123c20a523"

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2

[private]
default:
    @just --list

# List the images defined in images.json (compact JSON, used for the CI matrix)
[group('Utility')]
images:
    @jq -c . images.json

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# Builds one image from images.json using Podman.
#
# Arguments:
#   $target_image - An image name from images.json (a "localhost/" prefix is allowed).
#   $tag - The tag for the image (default: $default_tag).
#
# The image's base image, variant and optional features come from images.json
# and are passed to the Containerfile as build args. If the git working
# directory is clean, the labels also include the short SHA of the current HEAD.
#
# Example usage:
#   just build bazzite-bigscreen
#
# This will build an image 'localhost/bazzite-bigscreen:latest'

# Build an image from images.json
build $target_image $tag=default_tag:
    #!/usr/bin/env bash

    set -euox pipefail

    name="${target_image#localhost/}"
    entry=$(jq -ec --arg n "${name}" '.[] | select(.name == $n)' images.json) || {
        echo "Unknown image '${name}'. Known images: $(jq -r '[.[].name] | join(", ")' images.json)" >&2
        exit 1
    }
    # CI sets GITHUB_REPOSITORY_OWNER; local builds fall back to image-template.env
    vendor="${GITHUB_REPOSITORY_OWNER:-${repo_organization}}"
    vendor="${vendor,,}"
    repo="${GITHUB_REPOSITORY:-${repo_organization}/${repo_name}}"
    description=$(jq -r .description <<< "${entry}")

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=$(jq -r .base <<< "${entry}")")
    BUILD_ARGS+=("--build-arg" "VARIANT=$(jq -r .variant <<< "${entry}")")
    BUILD_ARGS+=("--build-arg" "FEATURES=$(jq -r '(.features // []) | join(" ")' <<< "${entry}")")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR=${vendor}")

    LABELS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/${repo}/${GIT_SHA}/README.md")
        LABELS+=("--label" "org.opencontainers.image.documentation=https://raw.githubusercontent.com/${repo}/${GIT_SHA}/README.md")
        LABELS+=("--label" "org.opencontainers.image.source=https://github.com/${repo}/blob/${GIT_SHA}/Containerfile")
        LABELS+=("--label" "org.opencontainers.image.revision=$(git rev-parse HEAD)")
        LABELS+=("--label" "org.opencontainers.image.url=https://github.com/${repo}/tree/${GIT_SHA}")
        LABELS+=("--label" "org.opencontainers.image.version=${tag}.$(date +%Y%m%d)-${GIT_SHA}")
    fi

    # Image metadata for https://artifacthub.io/ - This is optional but is highly recommended so we all can get a index of all the custom images
    # The metadata by itself is not going to do anything, you choose if you want your image to be on ArtifactHub or not.
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "io.artifacthub.package.keywords={{ image_keywords }}")
    LABELS+=("--label" "io.artifacthub.package.license=Apache-2.0")
    LABELS+=("--label" "io.artifacthub.package.logo-url={{ image_logo_url }}")
    LABELS+=("--label" "io.artifacthub.package.prerelease=false")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.description=${description}")
    LABELS+=("--label" "org.opencontainers.image.title=${name}")
    LABELS+=("--label" "org.opencontainers.image.vendor=${vendor}")

    # This actually builds the image!
    # --no-cache: podman's layer cache ignores the build scripts bind-mounted
    # from the ctx stage, so a cached RUN step could ship stale scripts. The dnf
    # package cache (a cache mount) still speeds up rebuilds.
    PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --pull=newer --no-cache --tag "${name}:${tag}" --file Containerfile)

    podman build "${PODMAN_BUILD_ARGS[@]}" .

# Split the image for smaller updates, keeping its labels (used by CI)
rechunk $target_image $tag=default_tag:
    #!/usr/bin/env bash

    set -xeuo pipefail

    # The image's config (labels, Env, Cmd) comes from `podman inspect` via --config.
    # Labels removed below describe the base image's build, not this one: its ostree
    # commit (pruned here), its rpm-ostree input hash and a Quay expiry setting.
    # You may run into space issues on github runners as we are making a
    # complete copy of the image, which likely has no shared layers, unless your
    # base image is also using chunkah
    CHUNKAH_CONFIG_FILE="$(mktemp)"

    # You may omit the current directory here if you are confident that you
    # won't run out of space on /tmp for your image
    CHUNKAH_OUTPUT_DIR="$(mktemp -d ./"${target_image}"_chunkah_XXXXXX)"

    trap 'rm -f "${CHUNKAH_CONFIG_FILE}"; rm -rf "${CHUNKAH_OUTPUT_DIR}"' EXIT
    podman inspect "${target_image}:${tag}" > "${CHUNKAH_CONFIG_FILE}"

    podman run --rm \
      --mount=type=image,src="${target_image}:${tag}",target=/chunkah \
      -v "${CHUNKAH_CONFIG_FILE}:/chunkah-config.json:ro,Z" \
      -v "${CHUNKAH_OUTPUT_DIR}:/run/out:Z" \
      "{{ chunkah_image }}" \
      build \
      --verbose \
      --compressed \
      --max-layers 128 \
      --prune /sysroot/ \
      --label ostree.commit- --label ostree.final-diffid- \
      --label rpmostree.inputhash- --label quay.expires-after- \
      --config /chunkah-config.json \
      --output oci:/run/out/chunked

    CHUNKED_IMAGE="$(podman pull "oci:${CHUNKAH_OUTPUT_DIR}/chunked")"
    podman tag "${CHUNKED_IMAGE}" "${target_image}:${tag}"

# Split the image for smaller updates (Classical). Drops the image's labels!
ostree-rechunk $target_image $tag=default_tag:
    #!/usr/bin/env bash

    set -xeuo pipefail

    # Use the already-built local image to avoid pulling from a remote registry
    RPM_OSTREE_CHUNKER_IMAGE="localhost/${target_image}:${tag}"

    GRAPHROOT="$(podman info --format '{{ '{{.Store.GraphRoot}}' }}')"

    podman run --rm --pull=never --privileged \
      --mount=type=image,src="${target_image}:${tag}",target=/rpm-ostree \
      --mount=type=bind,src=${GRAPHROOT},target=/run/host-container-storage,rw \
      --mount=type=tmpfs,target=/run/rpm-ostree-storage \
      --entrypoint /usr/bin/rpm-ostree \
      "${RPM_OSTREE_CHUNKER_IMAGE}" \
      compose build-chunked-oci \
      --max-layers 127 \
      --format-version=2 \
      --bootc \
      --rootfs /rpm-ostree \
      --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]localhost/${target_image}:${tag}"

# Generate Default Tag
[group('Utility')]
generate-default-tag $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    echo "${tag}"

# Generate Tags
[group('Utility')]
generate-build-tags $target_image $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    DATE=$(date +%Y%m%d)
    BUILD_TAGS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        BUILD_TAGS+=("${tag}-${GIT_SHA}")
        BUILD_TAGS+=("${tag}-${DATE}-${GIT_SHA}")
        BUILD_TAGS+=("${DATE}-${GIT_SHA}")
    fi

    BUILD_TAGS+=("${DATE}")
    BUILD_TAGS+=("${tag}")
    BUILD_TAGS+=("${tag}-${DATE}")

    echo "${BUILD_TAGS[@]}"

# Tag Images
[group('Utility')]
tag-images $target_image $tag=default_tag tags="":
    #!/usr/bin/env bash
    set -eoux pipefail

    # Get Image, and untag
    IMAGE=$(podman inspect ${target_image}:${tag} | jq -r .[].Id)
    podman untag ${IMAGE}

    # Tag Image
    for tag in {{ tags }}; do
        podman tag $IMAGE "${target_image}:${tag}"
    done

    # Show Images
    podman images

# Render disk_config/iso.toml.in for one image. The installed system switches to
# the published GHCR image after install, unless this is a local-only build
# (vendor "localhost"), which has no registry to track yet.
[private]
_iso-config $target_image $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    name="${target_image#localhost/}"
    vendor="${GITHUB_REPOSITORY_OWNER:-${repo_organization}}"
    vendor="${vendor,,}"
    out="_build_iso-${name}.toml"
    if [[ "${vendor}" == "localhost" ]]; then
        sed 's|^bootc switch .*|# local test build: no registry image to switch to yet|' disk_config/iso.toml.in > "${out}"
    else
        sed "s|__IMAGE_REF__|ghcr.io/${vendor}/${name}:${tag}|" disk_config/iso.toml.in > "${out}"
    fi
    echo "Rendered ${out}"

# Render the qcow2 config for one image, with a login user for the VM.
# bootc-image-builder disk images have no user account and Bazzite has no
# first-run wizard, so this asks for one. The rendered file is gitignored
# (_build_*), readable only by you, and deleted after the build.
[private]
_disk-config $target_image:
    #!/usr/bin/env bash
    set -euo pipefail

    name="${target_image#localhost/}"
    out="_build_disk-${name}.toml"
    read -rp "VM login username [tester]: " vm_user
    vm_user="${vm_user:-tester}"
    read -rsp "VM login password (not shown): " vm_pass
    echo
    if [[ ! "${vm_user}" =~ ^[a-z_][a-z0-9_-]*$ || -z "${vm_pass}" || "${vm_pass}" == *"'"* ]]; then
        echo "Use a lowercase username and a non-empty password without single quotes" >&2
        exit 1
    fi
    umask 077
    {
        cat disk_config/disk.toml
        echo
        echo '[[customizations.user]]'
        echo "name = \"${vm_user}\""
        echo "password = '${vm_pass}'"
        echo 'groups = ["wheel"]'
    } > "${out}"
    echo "Rendered ${out} (deleted after the build)"

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: disk_config/disk.toml)

# Example: just _build-bib localhost/bazzite-bigscreen latest qcow2 disk_config/disk.toml
_build-bib $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -euo pipefail

    # A rendered qcow2 config holds the VM password: remove it whatever happens
    trap '[[ "${config}" != _build_disk-* ]] || rm -f "${config}"' EXIT

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    # bootc-image-builder reads the image from root's podman storage. It is copied
    # there from yours, or pulled if you don't have it; root keeps it between builds.
    user_id=$(podman images --filter reference="${target_image}:${tag}" --format "{{ '{{.ID}}' }}")
    COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    # Keep each image's output apart: output/<image>/{qcow2,bootiso}/
    dest="output/$(basename "${target_image}")"

    # One sudo call for the image copy, the build and the copy-out. The copy and
    # the build each run longer than sudo's credential cache, so a second sudo
    # would ask for the password again, and give up after 5 minutes if nobody answers.
    sudo bash -euo pipefail -c '
      buildtmp=$1 dest=$2 owner=$3 config=$4 bib_image=$5 image=$6 user_id=$7 copytmp=$8
      shift 8
      if [[ -z "${user_id}" ]]; then
        podman pull "${image}"
      elif [[ "$(podman images --filter reference="${image}" --format "{{ '{{.ID}}' }}")" != "${user_id}" ]]; then
        TMPDIR="${copytmp}" podman image scp "${owner%%:*}@localhost::${image}" "root@localhost::${image}"
      fi
      rm -rf "${copytmp}"
      podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --net=host \
        --security-opt label=type:unconfined_t \
        -v "${config}:/config.toml:ro" \
        -v "${buildtmp}:/output" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "${bib_image}" \
        "$@" \
        "${image}"
      mkdir -p "${dest}"
      cp -rf "${buildtmp}/." "${dest}/"
      rm -rf "${buildtmp}"
      chown -R "${owner}" output/
    ' bib "${BUILDTMP}" "${dest}" "$(id -u):$(id -g)" "$(pwd)/${config}" "${bib_image}" "${target_image}:${tag}" "${user_id}" "${COPYTMP}" ${args}
    echo "Disk image(s) written to ${dest}/"

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/bazzite-bigscreen latest qcow2 disk_config/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image (import it in virt-manager)
[group('Build Virtual Machine Image')]
build-qcow2 $image $tag=default_tag: (_disk-config image) && (_build-bib ("localhost/" + image) tag "qcow2" ("_build_disk-" + image + ".toml"))

# Build an Anaconda installer ISO (boot it in virt-manager to test the real install path)
[group('Build Virtual Machine Image')]
build-iso $image $tag=default_tag: (_iso-config image tag) && (_build-bib ("localhost/" + image) tag "iso" ("_build_iso-" + image + ".toml"))

# Rebuild the container image, then a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
rebuild-qcow2 $image $tag=default_tag: (_disk-config image) && (_rebuild-bib ("localhost/" + image) tag "qcow2" ("_build_disk-" + image + ".toml"))

# Rebuild the container image, then an Anaconda installer ISO
[group('Build Virtual Machine Image')]
rebuild-iso $image $tag=default_tag: (_iso-config image tag) && (_rebuild-bib ("localhost/" + image) tag "iso" ("_build_iso-" + image + ".toml"))

# Needs the qcow2 from `just build-qcow2 <image>`. No sudo: the disk is uploaded
# into libvirt's default storage pool through libvirt itself. The VM appears in
# virt-manager under QEMU/KVM as "<image>-test".
# Settings: VM_MEMORY (MiB), VM_VCPUS, VM_RENDERNODE, LIBVIRT_DEFAULT_URI.
# Create and start a test VM from the built qcow2
[group('Build Virtual Machine Image')]
vm $image:
    #!/usr/bin/env bash
    set -euo pipefail

    disk="output/${image}/qcow2/disk.qcow2"
    if [[ ! -f "${disk}" ]]; then
        echo "No ${disk} yet. Build it first (asks for a VM login and your sudo password):" >&2
        echo "  just build-qcow2 ${image}" >&2
        exit 1
    fi
    uri="${LIBVIRT_DEFAULT_URI:-qemu:///system}"
    name="${image}-test"
    vol="${name}.qcow2"
    virsh=(virsh --connect "${uri}")

    if "${virsh[@]}" dominfo "${name}" &>/dev/null; then
        echo "VM '${name}' already exists. To replace it with the new disk, remove it first:" >&2
        echo "  virsh -c ${uri} destroy ${name}; virsh -c ${uri} undefine ${name} --nvram --remove-all-storage" >&2
        exit 1
    fi
    "${virsh[@]}" pool-refresh default >/dev/null
    if "${virsh[@]}" vol-info --pool default "${vol}" &>/dev/null; then
        echo "A disk '${vol}' from an earlier run is still in the default pool. Remove it first:" >&2
        echo "  virsh -c ${uri} vol-delete --pool default ${vol}" >&2
        exit 1
    fi

    # 3D acceleration: use the first render node that isn't NVIDIA's (the Intel or AMD
    # GPU); virgl on the proprietary NVIDIA driver is unreliable.
    render="${VM_RENDERNODE:-}"
    if [[ -z "${render}" ]]; then
        for node in /sys/class/drm/renderD*; do
            [[ "$(basename "$(readlink -f "${node}/device/driver")")" == nvidia ]] && continue
            render="/dev/dri/$(basename "${node}")"
            break
        done
    fi
    if [[ -n "${render}" ]]; then
        graphics=(--graphics "spice,listen=none,gl.enable=yes,gl.rendernode=${render}"
                  --video "model.type=virtio,model.acceleration.accel3d=yes")
    else
        echo "No usable render node found; the VM gets 2D graphics only." >&2
        graphics=(--graphics "spice" --video "model.type=virtio")
    fi

    # libvirt's default network is defined but may not be running. (awk, not grep -q:
    # grep -q exits early, and the resulting SIGPIPE fails the pipe under pipefail.)
    active=$("${virsh[@]}" net-info default | awk '{ sub(/\r$/, "") } $1 == "Active:" { print $2 }')
    if [[ "${active}" != yes ]]; then
        "${virsh[@]}" net-start default
    fi

    echo "Uploading ${disk} ($(du -h "${disk}" | cut -f1)) into the default pool as ${vol}..."
    "${virsh[@]}" vol-create-as default "${vol}" "$(stat -c %s "${disk}")" --format raw >/dev/null
    "${virsh[@]}" vol-upload --pool default "${vol}" "${disk}"
    "${virsh[@]}" pool-refresh default >/dev/null

    # UEFI without Secure Boot: the image's kernel is signed with Universal Blue's key,
    # which the VM firmware doesn't know.
    virt-install --connect "${uri}" \
        --name "${name}" \
        --osinfo fedora-unknown \
        --memory "${VM_MEMORY:-8192}" \
        --vcpus "${VM_VCPUS:-4}" \
        --cpu host-passthrough \
        --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
        --import \
        --disk "path=$("${virsh[@]}" vol-path --pool default "${vol}"),format=qcow2,bus=virtio" \
        --network network=default,model.type=virtio \
        --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        "${graphics[@]}" \
        --noautoconsole

    echo
    echo "VM '${name}' is booting. Open virt-manager and double-click it to see the console."

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
