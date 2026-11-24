<!-- Research notes gathered 2026-11-22 by a research subagent (web + GitHub/registry APIs). -->

# Building custom Bazzite-derived images in November 2026: research notes

Everything below was checked on 2026-11-22. Sources were the GitHub raw files and API, anonymous GHCR registry queries, the Fedora mdapi and COPR APIs, and the official docs. `gh` and `skopeo` are not installed on this machine, so I used `curl` against the same APIs. docs.fedoraproject.org blocked the fetch (Anubis bot protection), so I used the upstream bootc docs in their GitHub repo instead.

---

## 1. Recommended approach: ublue-os/image-template vs BlueBuild

### Takeaway
Universal Blue still recommends ublue-os/image-template, and it is actively maintained (last commit 2026-11-07). BlueBuild is also active, but Universal Blue does not support it, and its ISO path relies on an archived project. Neither template builds multiple variants out of the box. BlueBuild documents a recipe matrix; image-template needs hand edits to its Containerfile and Justfile.

### Cited findings

**image-template file tree today** ([repo](https://github.com/ublue-os/image-template)):
```
.github/dependabot.yml
.github/renovate.json5
.github/workflows/build.yml
.github/workflows/build-disk.yml
.gitignore  Containerfile  Justfile  LICENSE  README.md  artifacthub-repo.yml
build_files/build.sh
disk_config/disk.toml  disk_config/iso-gnome.toml  disk_config/iso-kde.toml
image-template.env
system_files/etc/.gitkeep  system_files/usr/.gitkeep
```
- There is no `cosign.pub` in the template. The README tells you to run `COSIGN_PASSWORD="" cosign generate-key-pair`, store `cosign.key` as the `SIGNING_SECRET` repo secret, and `git add ... cosign.pub` ([README](https://github.com/ublue-os/image-template/blob/main/README.md)).
- **Containerfile** ([source](https://github.com/ublue-os/image-template/blob/main/Containerfile)):
  - A `FROM scratch AS ctx` stage copies `build_files` to `/` and `system_files` to `/system_files`.
  - The base is `FROM ghcr.io/ublue-os/bazzite:stable`, hard-coded, with no ARG.
  - A single `RUN` with `--mount=type=bind,from=ctx,...,target=/ctx`, caches on `/var/cache` and `/var/log`, and a tmpfs on `/tmp` runs `/ctx/build.sh`.
  - The last line is `RUN bootc container lint`.
  - A commented-out option makes `/opt` immutable: `RUN rm /opt && mkdir /opt`.
- **build.sh** ([source](https://github.com/ublue-os/image-template/blob/main/build_files/build.sh)) does `cp -avf "/ctx/system_files"/. /`, then `dnf5 install -y tmux`, then `systemctl enable podman.socket`. Commented examples show the COPR pattern: `dnf5 -y copr enable …` / `dnf5 -y copr disable …`.
- **image-template.env** sets `IMAGE_NAME`, `REPO_ORGANIZATION`, `IMAGE_DESC`, `IMAGE_KEYWORDS`, `IMAGE_LOGO_URL`, `DEFAULT_TAG="latest"` and `BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"` ([source](https://github.com/ublue-os/image-template/blob/main/image-template.env)).
- **Justfile recipes** ([source](https://github.com/ublue-os/image-template/blob/main/Justfile)):
  - Build and publish: `build`, `rechunk` (chunkah), `ostree-rechunk` (rpm-ostree), `generate-build-tags`, `tag-images`.
  - Disk images and VMs: `build-qcow2`/`build-raw`/`build-iso` (and `rebuild-*`), `run-vm-qcow2`/`run-vm-iso`, `spawn-vm` (systemd-vmspawn).
  - Housekeeping: `check`, `fix`, `lint` (shellcheck), `format` (shfmt), `clean`.
  - `build` creates an empty `BUILD_ARGS=()` and never fills it, so the Containerfile receives no `--build-arg` values.
- **build.yml** ([source](https://github.com/ublue-os/image-template/blob/main/.github/workflows/build.yml)):
  - Triggers: PRs, a daily cron `05 10 * * *`, pushes to `main`, and manual dispatch. Runs on `runs-on: ubuntu-26.04`.
  - Steps in order: `ublue-os/remove-unwanted-software` → `just check` → `just build` → `just ostree-rechunk` (chunkah is offered as a commented-out alternative) → tag → `podman push` to GHCR → cosign sign.
  - Push and sign only run on the default branch.
  - Actions used: `cosign-installer` v4.1.3 with `cosign-release: 'v3.1.4'`, and `actions/checkout` v7.
  - Tags produced: `latest`, `latest-<sha>`, `latest-<YYYYMMDD>-<sha>`, `<YYYYMMDD>-<sha>`, `<YYYYMMDD>`, `latest-<YYYYMMDD>`.
- **Recent maintenance** ([commits](https://github.com/ublue-os/image-template/commits/main)):
  - 2026-11-07: README docs on adding NVIDIA drivers.
  - 2026-11-05: cosign bumped to v3.1.4 and login-action to v4.8.0.
  - 2026-10-12: "chore: don't pin bazzite (#282)".
  - Before that, Renovate had pinned the bazzite tag to a digest (#275, 2026-09-04).
- **Multi-image examples.** The README lists community repos built on this template: m2os, bOS, Homer, Amy OS and VeneOS ([README](https://github.com/ublue-os/image-template/blob/main/README.md)).
- **Bazzite docs** list three options: (A) image-template, "recommended" over forking; (B) fork Bazzite and sync it with the Pull app; (C) BlueBuild, with the note that "All support for Blue-Build images should be directed to the appropriate communication channels outside of Universal Blue" ([docs.bazzite.gg](https://docs.bazzite.gg/Advanced/creating_custom_image/)). Bazzite's own Containerfile header also points people to image-template ([Containerfile](https://github.com/ublue-os/bazzite/blob/main/Containerfile)).

**BlueBuild**
- **Template tree** ([repo](https://github.com/blue-build/template)): `.github/workflows/build.yml`, `cosign.pub`, `files/scripts/example.sh`, `files/system/{etc,usr}`, `modules/`, `recipes/recipe.yml`. Last pushed 2026-11-20.
- **Recipe format:** `name`, `description`, `base-image`, `image-version`, and an ordered `modules:` list. The template uses `files`, `dnf` (with `repos.copr`, `install.packages`, `remove.packages`), `default-flatpaks` and `signing` ([recipe.yml](https://github.com/blue-build/template/blob/main/recipes/recipe.yml)).
- **Workflow:** a matrix over `recipe:` that calls `blue-build/github-action@v1.13` with `cosign_private_key: ${{ secrets.SIGNING_SECRET }}`, `registry_token`, `pr_event_number` and `maximize_build_space: true` ([build.yml](https://github.com/blue-build/template/blob/main/.github/workflows/build.yml)).
  - The template still references v1.13, but the latest action release is v1.14.0 (2026-11-09). The latest CLI is v0.9.42 (2026-11-08), and none of the repos are archived (GitHub API).
- **Multiple images:** one recipe file per image (for example `recipe-gnome.yml`, `recipe-kde.yml`), each with a unique `name`, all listed in the workflow matrix ([multiple-images](https://blue-build.org/how-to/multiple-images/)). Shared configuration goes in split files ([multiple-files](https://blue-build.org/how-to/multiple-files/)).
- **Action inputs** include `chunkah`, `build_chunked_oci`, `max_layers` (default 128), `rechunk`, `use_cache`, `squash` and `build_opts`. The `rechunk` input is flagged: "This option will be deprecated in the future" ([action reference](https://blue-build.org/reference/github-action/)).

### Inferences
- With image-template, two variants from one repo means four edits: add `ARG BASE_IMAGE` before `FROM`, make the Justfile pass `--build-arg`, put a matrix in build.yml, and parameterise `IMAGE_NAME` per matrix leg. `just build <target_image> <tag>` already accepts the image name as an argument, but the OCI labels still read `image_name` from the env file.
- BlueBuild handles multiple variants natively, but you trade away Universal Blue support and get a weaker ISO story (section 4).

### Gaps
- I did not fetch the content of the BlueBuild "multiple-files" page (for example the exact `from-file:` syntax).
- A third-party "Atomic Image Builder" was posted on the Universal Blue forum (2026-07-08). UNVERIFIED; I did not evaluate it.

---

## 2. Bazzite base images, tags, Fedora and Plasma versions

### Takeaway
Bazzite is on Fedora 45 (released 2026-11-03). Stable is `45.20261117.1`, with kernel `7.3.4-ogc8.1.fc45` and KDE reported as 6.8.3. Images are x86_64-only, and the tag scheme is `stable` / `testing` / `unstable`, each with a `-45` suffix variant.

### Cited findings
- **The 14 image names** in the build.py `IMAGES` table, with base, Containerfile target and NVIDIA flavor ([build.py](https://github.com/ublue-os/bazzite/blob/main/build.py)):

  | Image | Base | Target | NVIDIA |
  |---|---|---|---|
  | `bazzite` | kinoite | bazzite | none |
  | `bazzite-gnome` | silverblue | bazzite | none |
  | `bazzite-deck` | kinoite | bazzite-deck | none |
  | `bazzite-deck-gnome` | silverblue | bazzite-deck | none |
  | `bazzite-deck-nvidia` | kinoite | bazzite-nvidia | nvidia-open |
  | `bazzite-deck-nvidia-gnome` | silverblue | bazzite-nvidia | nvidia-open |
  | `bazzite-nvidia` | kinoite | bazzite-nvidia | **nvidia-lts**, `ogc-lts` kernel `6.18.64-ogc1.1.fc45` |
  | `bazzite-gnome-nvidia` | silverblue | bazzite-nvidia | nvidia-lts |
  | `bazzite-nvidia-open` | kinoite | bazzite-nvidia | nvidia-open |
  | `bazzite-gnome-nvidia-open` | silverblue | bazzite-nvidia | nvidia-open |
  | `bazzite-dx` | kinoite | bazzite-dx | none |
  | `bazzite-dx-gnome` | silverblue | bazzite-dx | none |
  | `bazzite-dx-nvidia` | kinoite | bazzite-dx | nvidia-open |
  | `bazzite-dx-nvidia-gnome` | silverblue | bazzite-dx | nvidia-open |

  The Bazzite 45 forum post says "Ten images are built" ([forum, 2026-11-03](https://universal-blue.discourse.group/t/bazzite-45-is-here/12702)). That conflicts with the 14 rows in build.py; the dx images may have been added later.
- **Build defaults:** `fedora_version: 45`, `kernel_flavor: "ogc"`, `kernel_version: "7.3.4-ogc10.1.fc45"`, `arch: "x86_64"` ([build.py](https://github.com/ublue-os/bazzite/blob/main/build.py)).
- **Tag logic** (`alias_tags()`):
  - Stable builds get `stable-{version}`, `latest`, `stable` and `stable-{fedora}`.
  - Testing builds get `testing` and `testing-45`; unstable builds get `unstable` and `unstable-45`.
  - The version format is `{fedora}.{YYYYMMDD}`, with `.N` point-release suffixes and `testing-`/`unstable-` prefixes ([build.py](https://github.com/ublue-os/bazzite/blob/main/build.py)).
- **GHCR check** (anonymous registry API). `stable`, `stable-45`, `testing-45`, `unstable-45` and `stable-44` all return 200 for bazzite, bazzite-deck, bazzite-gnome, bazzite-deck-gnome, bazzite-nvidia, bazzite-gnome-nvidia-open, bazzite-deck-nvidia and bazzite-dx-nvidia. A bare `45` tag returns 404. Upstream `ghcr.io/ublue-os/kinoite-main:45` exists ([GHCR packages](https://github.com/orgs/ublue-os/packages)).
- **Labels on `bazzite:stable`:**
  - `org.opencontainers.image.version=45.20261117.1`, created 2026-11-17, `ostree.linux=7.3.4-ogc8.1.fc45.x86_64`.
  - The manifest is a single-arch manifest with 256 layers, not a multi-arch index.
  - `bazzite:testing` is `testing-45.20261122.3`, with kernel `7.3.4-ogc10.1`.
- **Release notes for stable 45.20261117.1:** KDE 6.8.3-1, GNOME 51.1-1, Mesa 26.2.7 ([release](https://github.com/ublue-os/bazzite/releases/tag/45.20261117.1)). Testing and unstable also show KDE 6.8.3-1, plus Nvidia Open 620.73.04 and Nvidia LTS 580.196.07 ([releases](https://github.com/ublue-os/bazzite/releases)).
- **Bazzite 45 launch post:** "Bazzite is now based on Fedora 45!", with "GNOME 51.1 and KDE 6.8.2" at launch; "Chunkah is now in use"; chunks are zstd-compressed ([forum](https://universal-blue.discourse.group/t/bazzite-45-is-here/12702)).
- **Desktop vs deck images:**
  - Deck images install and enable `sddm`, remove `plasma-login-manager`, swap `steamdeck-kde-presets-desktop` for `steamdeck-kde-presets`, and disable GDM on Silverblue ([bazzite-deck/01-configure-desktop.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/01-configure-desktop.sh)).
  - Deck images install gamescope-session-plus plus a Steam bootstrap archive ([03-install-gamescope-session.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/03-install-gamescope-session.sh)).
  - `bazzite-autologin` writes the SDDM autologin session `gamescope-session-ogui-steam.desktop`, unless `/etc/bazzite/desktop_autologin` exists, in which case it picks `plasma.desktop` or `gnome.desktop` based on `base-image-name` ([bazzite-autologin](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/bazzite-autologin)).
  - Desktop KDE images ship a `plasma-login-manager` config at `system_files/desktop/kinoite/usr/lib/plasmalogin/defaults.conf` ([tree](https://github.com/ublue-os/bazzite/tree/main/system_files/desktop/kinoite)).
- **Fedora 45 package availability** ([mdapi](https://mdapi.fedoraproject.org/f45/pkg/plasma-bigscreen); [COPR](https://copr.fedorainfracloud.org/coprs/swayfx/swayfx/)):
  - `plasma-bigscreen` 6.8.1-1.fc45 is in the Fedora 45 repos.
  - `swayfx` is not in the Fedora 45 repos. COPR `swayfx/swayfx` has a `fedora-45-x86_64` chroot.
  - Stock `sway` 1.12 is in Fedora 45.

### Inferences
- KDE version discrepancy: Bazzite's notes say KDE 6.8.3-1, but mdapi shows Fedora's `plasma-workspace`/`kwin` at 6.8.1 in f45-updates and updates-testing. A `plasma-bigscreen` 6.8.1 install could hit version pins, or mdapi may just be lagging. Check inside the image before committing to a plan: `podman run --rm ghcr.io/ublue-os/bazzite:stable rpm -q plasma-workspace plasma-bigscreen`.
- Bazzite is x86_64-only, so the template's arm64 disk-build option does not apply.

### Gaps
- I could not find where the KDE 6.8.3 builds come from. None of the `ublue-os/staging`, `ublue-os/bazzite` or `ublue-os/packages` COPRs have plasma-workspace or kwin builds. UNVERIFIED.

---

## 3. How Bazzite itself is built, and whether to remove KDE

### Takeaway
Since Fedora 45, Bazzite is built from a short single-stage Containerfile, numbered scripts under `build_files/`, and a `build.py` orchestrator. A lot of it assumes the desktop is either `kinoite` (KDE) or `silverblue` (GNOME). Adding a session alongside KDE is much safer than removing Plasma.

### Cited findings
- **Containerfile** ([source](https://github.com/ublue-os/bazzite/blob/main/Containerfile)):
  - ARGs: `BASE_IMAGE_NAME=kinoite`, `FEDORA_VERSION=45`, `BASE_IMAGE=ghcr.io/ublue-os/${BASE_IMAGE_NAME}-main:${FEDORA_VERSION}`, `KERNEL_FLAVOR=ogc`, `NVIDIA_FLAVOR`, and `BUILD_DECK`/`BUILD_NVIDIA`/`BUILD_DX`.
  - Image stages pulled in:
    - `ghcr.io/ublue-os/akmods:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION}`
    - `akmods-extra`
    - `akmods-${NVIDIA_FLAVOR}`
    - `ghcr.io/ublue-os/brew` (pinned by digest)
    - scratch `ctx` and `system_files` stages
  - Build runs `build.sh` with many bind mounts and a `GITHUB_TOKEN` secret mount, then `image-info.sh && build-initramfs.sh && finalize.sh && cleanup.sh`, then `RUN --mount=type=tmpfs,target=/run --network=none bootc container lint`.
  - The forum post says the Containerfile went from "800+" to "102" lines, with stages collapsed and deck/NVIDIA additions applied through build args ([forum](https://universal-blue.discourse.group/t/bazzite-45-is-here/12702)).
- **build_files layout** ([tree](https://github.com/ublue-os/bazzite/tree/main/build_files)):
  - `bazzite/01-copy-brew-files.sh` … `12-finalize.sh`, including `03-install-kernel-akmods.sh`, `04-initialize.sh`, `06-global-remove.sh` and `10-configure-desktops.sh`.
  - `bazzite/desktop_env/{configure-kde.sh,configure-gnome.sh,build-gnome-extensions.sh}`.
  - Per-variant folders `bazzite-deck/`, `bazzite-nvidia/`, `bazzite-dx/`.
  - Shared scripts `image-info.sh`, `build-initramfs.sh`, `finalize.sh`, `cleanup.sh`, and helpers in `tools/` (`dnf5-setopt`, `install-kmods`, `ghcurl`, …).
- **system_files layout:**
  - `system_files/{desktop,deck,nvidia}/{shared,kinoite,silverblue}/…`, plus `system_files/dx/` and `system_files/overrides/`.
  - ujust recipes live in `usr/share/ublue-os/just/*.just`: `80-bazzite.just` … `98-bazzite-htpc-auto-hdr.just`, `kinoite/.../90-bazzite-de.just` and `95-bazzite-deck-session.just` ([tree](https://github.com/ublue-os/bazzite/tree/main/system_files)).
- **KDE-specific customisation in `configure-kde.sh`** ([source](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/desktop_env/configure-kde.sh)):
  - Installs `steamdeck-kde-presets-desktop`, `krunner-bazaar`, `krunner-yafti` and others.
  - Removes `plasma-welcome`, `plasma-discover`, `plasma-setup`, `xwaylandvideobridge` and others.
  - Patches `/usr/share/plasma/layout-templates/.../layout.js` with `bazzite-pins.js` and sets wallpapers.
  - KDE files also land in `/etc/skel/.config/gtk-4.0/*.css`, `/etc/xdg/kcm-about-distrorc`, `/etc/xdg/QtProject/qtlogging.ini` and `/usr/share/kde-settings/kde-profile/default/xdg/{kicker-extra-favoritesrc,krunnerrc}` ([tree](https://github.com/ublue-os/bazzite/tree/main/system_files/desktop/kinoite)).
- **Scripts that assume KDE or GNOME:**
  - `10-configure-desktops.sh` branches on `BASE_IMAGE_NAME == kinoite`.
  - `os-session-select` maps to `plasma.desktop` or `gnome.desktop` from `/usr/share/ublue-os/image-info.json` `base-image-name` ([os-session-select](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/os-session-select)).
  - `bazzite-autologin` does the same and exits for an unknown base.
  - `bazzite-desktop-bootstrap` calls `gnome-randr`.
- **image-info.json** is written with `image-name`, `image-vendor`, `image-ref` (`ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}`), `image-tag`, `image-branch`, `base-image-name` and `fedora-version`. The same step rewrites `/usr/lib/os-release` ([image-info.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/image-info.sh)).
- **Docs stance:** Bazzite docs list "Use a different desktop environment or window manager than Bazzite offers" as a valid custom-image use case ([docs](https://docs.bazzite.gg/Advanced/creating_custom_image/)). The rebase guide says "Do **not** rebase between different desktop environments" ([rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/)).

### Inferences
- A derived image inherits `image-info.json` with `image-name: bazzite` and `vendor: ublue-os`. Rewrite those fields, keeping `base-image-name: kinoite` so the KDE branches keep working, so that ujust and rebase helpers point at your image. Which helpers actually read `image-ref` is UNVERIFIED.
- Removing Plasma would break deck session switching, autologin, presets and ujust recipes. Keep Plasma and add SwayFX as an extra Wayland session.
- Plasma Bigscreen is a Plasma shell, so it fits a KDE base. On a deck base the default autologin target is gamescope, and the desktop fallback is hard-coded to `plasma.desktop`. You would need to override `/etc/sddm.conf.d` or the desktop session to land on Bigscreen. The Bigscreen session file name (for example `plasma-bigscreen-wayland.desktop`) is UNVERIFIED.

### Gaps
- I did not read `06-global-remove.sh` or all of the ujust recipes.
- I did not check whether plasma-login-manager lists third-party sessions such as SwayFX.

---

## 4. Signing, rechunking, linting, ISOs and install commands

### Takeaway
- **Signing:** use a cosign key pair, with cosign v3 run in the legacy bundle format.
- **Rechunking:** rpm-ostree `build-chunked-oci` is the template default. chunkah is the newer option, and Bazzite now uses it.
- **ISOs:** the tools changed a lot in 2026. The BIB GitHub Action and BlueBuild's ISO backend are both archived or deprecated. Titanoboa (what Bazzite uses) and `osbuild/image-builder-action` are the current paths.

### Cited findings
- **Signing command** in the template, with a comment linking containers/container-libs#388 and coreos/rpm-ostree#5509 ([build.yml](https://github.com/ublue-os/image-template/blob/main/.github/workflows/build.yml)):
  ```
  cosign sign -y --new-bundle-format=false --use-signing-config=false --key env://COSIGN_PRIVATE_KEY ${IMAGE_REGISTRY}/${IMAGE_NAME}@${DIGEST}
  ```
  Bazzite's `build.py sign` uses the same flags ([build.py](https://github.com/ublue-os/bazzite/blob/main/build.py)).
- **Client-side verification policy.** Universal Blue's `policy.json` defaults to `reject`, requires `sigstoreSigned` for `ghcr.io/ublue-os` (keys `/etc/pki/containers/ublue-os.pub` and `ublue-os-backup.pub`), and sets `insecureAcceptAnything` for every other docker registry. `registries.d/ublue-os.yaml` sets `use-sigstore-attachments: true` ([policy.json](https://github.com/ublue-os/packages/blob/main/packages/ublue-os-signing/src/usr/etc/containers/policy.json)).
  - So an unconfigured `ghcr.io/<you>/…` image is pulled without verification.
  - BlueBuild's `signing` module adds a `sigstoreSigned` entry keyed to `/etc/pki/containers/<image>.pub` and writes a registries.d file ([signing.sh](https://github.com/blue-build/modules/blob/main/modules/signing/signing.sh)).
- **Rechunking:**
  - Template `ostree-rechunk` runs `rpm-ostree compose build-chunked-oci --max-layers 127 --format-version=2 --bootc --rootfs /rpm-ostree --output containers-storage:…` inside the built image.
  - Template `rechunk` runs `quay.io/coreos/chunkah:latest build --compressed --max-layers 128 --prune /sysroot/ --label ostree.commit- --label ostree.final-diffid-`. The Justfile warns that chunkah makes "a complete copy of the image" and may exhaust runner disk ([Justfile](https://github.com/ublue-os/image-template/blob/main/Justfile)).
  - Bazzite uses chunkah pinned by digest and cosign-verifies the chunkah image ([build.yml](https://github.com/ublue-os/bazzite/blob/main/.github/workflows/build.yml); [chunkah](https://github.com/coreos/chunkah), active as of 2026-11-16).
- **Linting:** `bootc container lint` supports `--fatal-warnings`, `--skip`, `--list` and `--no-truncate` ([man page](https://github.com/bootc-dev/bootc/blob/main/docs/src/man/bootc-container-lint.8.md)).
  - Neither the template nor Bazzite uses `ostree container commit` any more; both end with `bootc container lint`.
- **ISO tool status:**
  - `osbuild/bootc-image-builder-action` is archived. Its README says "This action is deprecated. Migrate to osbuild/image-builder-action" ([repo](https://github.com/osbuild/bootc-image-builder-action)).
  - The template's build-disk.yml still uses it, pinned to commit `8661cd3`, with a matrix over `qcow2` and `anaconda-iso` ([build-disk.yml](https://github.com/ublue-os/image-template/blob/main/.github/workflows/build-disk.yml)).
  - BIB's sources "are now located in osbuild/image-builder" ([BIB repo](https://github.com/osbuild/bootc-image-builder)).
- **Template ISO bug:** build-disk.yml and the Justfile `build-iso` reference `./disk_config/iso.toml`, but the repo only ships `iso-gnome.toml` and `iso-kde.toml`. `iso-kde.toml` contains a kickstart `%post` line, `bootc switch --mutate-in-place --transport registry ghcr.io/ublue-os/image-template:latest`, which you must change to your own image ([iso-kde.toml](https://github.com/ublue-os/image-template/blob/main/disk_config/iso-kde.toml)).
- **image-builder-action replacement:** `osbuild/image-builder-action@v1` with `image_type: bootc-generic-iso`, `bootc_ref` (an installer container that includes Anaconda) and `bootc_installer_payload_ref` (the image to install). For disks: `bootc_ref` plus `bootc_default_fs: btrfs` plus `image_type: qcow2` ([README](https://github.com/osbuild/image-builder-action)).
- **Titanoboa (Bazzite's ISO path):**
  - The image must contain `/usr/lib/bootc-image-builder/iso.yaml` (label and GRUB2 entries), per the "Container-native ISO contract v0.1.0" ([titanoboa](https://github.com/ublue-os/titanoboa)). The repo was last pushed 2026-06-18.
  - Bazzite builds `installer/Containerfile` on top of the image with `podman build --cap-add sys_admin --security-opt label=disable --build-arg BASE_IMAGE=… --build-arg INSTALL_IMAGE_PAYLOAD=… --build-arg FLATPAK_DIR_SHORTNAME=kde_flatpaks`, then calls `ublue-os/titanoboa@5c457c3…` with `image-ref: localhost/payload:latest` and `iso-dest: …-live-amd64.iso`.
  - It then signs the ISO with `cosign sign-blob -y --key env://SIGNING_KEY "$iso" --output-signature "${iso}.sig"` and runs `actions/attest-build-provenance` ([build_iso.yml](https://github.com/ublue-os/bazzite/blob/main/.github/workflows/build_iso.yml); [installer/](https://github.com/ublue-os/bazzite/tree/main/installer)).
- **BlueBuild ISO is stale:** `sudo bluebuild generate-iso --iso-name weird-os.iso image ghcr.io/octocat/weird-os` uses JasonN3's build-container-installer ([docs](https://blue-build.org/how-to/generate-iso/); the CLI still hard-codes `JASONN3_INSTALLER_IMAGE` in [generate_iso.rs](https://github.com/blue-build/cli/blob/main/src/commands/generate_iso.rs)). That repo is now **archived** ([repo](https://github.com/JasonN3/build-container-installer)).
- **ISO hosting:** the template uploads to Actions artifacts or to S3 via rclone (secrets `S3_PROVIDER`, `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`, `S3_ENDPOINT`) ([README](https://github.com/ublue-os/image-template/blob/main/README.md)). BlueBuild notes that ISOs "cannot unfortunately be distributed on GitHub for free due to large sizes" ([template README](https://github.com/blue-build/template/blob/main/README.md)).
- **Install and rebase commands:**
  - `sudo bootc switch ghcr.io/<username>/<image_name>` ([template README](https://github.com/ublue-os/image-template/blob/main/README.md)).
  - `bootc switch --enforce-container-sigpolicy …` ("inverse of the previous `--target-no-signature-verification`"); `--apply` reboots into the new image; `--transport` accepts registry, oci, oci-archive, containers-storage ([bootc-switch](https://github.com/bootc-dev/bootc/blob/main/docs/src/man/bootc-switch.8.md)).
  - BlueBuild's two-step rebase: `rpm-ostree rebase ostree-unverified-registry:ghcr.io/<u>/<img>:latest`, reboot, then `rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<u>/<img>:latest` ([template README](https://github.com/blue-build/template/blob/main/README.md)).
  - Bazzite: `brh rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-deck:stable` and `rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/IMAGE:TAG`. List tags with `skopeo list-tags docker://ghcr.io/ublue-os/bazzite | grep -E "\bstable-" | sort -rV` ([rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/)).
  - Local image: `sudo bootc switch --transport containers-storage localhost/myimage:latest` ([template README](https://github.com/ublue-os/image-template/blob/main/README.md)).

### Inferences
- Commit `cosign.pub` to the repo and bake a policy.json entry, a registries.d file and the `.pub` key into the image. Without that, `ostree-image-signed` and `--enforce-container-sigpolicy` give you no real verification for your namespace.
- Checking a published image with `cosign verify --key cosign.pub ghcr.io/<u>/<img>:latest` is standard cosign usage. I did not test it against the legacy bundle format.

### Gaps
- I did not verify GitHub Releases asset size limits.
- I did not check whether `bootc-generic-iso` works with Bazzite payloads.

---

## 5. Build-script gotchas

### Takeaway
- Treat the Bazzite kernel as locked.
- Re-enable COPRs only for the duration of the build and disable them again.
- Never ship state in `/var`.
- Budget for 14 GB of runner disk.

### Cited findings
- **dnf5 and repos:**
  - Bazzite enables COPRs `ublue-os/{bazzite,bazzite-multilib,staging,packages}` at priority 98, plus Terra ([04-initialize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/04-initialize.sh)).
  - At the end, `finalize.sh` disables all of those COPRs and the `tailscale-stable`, `fedora-multimedia*`, `terra*` and `ublue-os:akmods` repos, and sets `skip_if_unavailable=1` ([finalize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/finalize.sh)).
  - In a derived build those repos are therefore present but disabled. Enable a repo for one transaction (for example `dnf5 -y install --enable-repo=…`), or enable then disable it, as the template comments show ([build.sh](https://github.com/ublue-os/image-template/blob/main/build_files/build.sh)).
- **Kernel and akmods:**
  - Bazzite erases the stock kernel, installs the ogc kernel RPMs from the akmods image, and runs `dnf5 versionlock add kernel kernel-devel kernel-devel-matched kernel-core kernel-modules` ([03-install-kernel-akmods.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/03-install-kernel-akmods.sh)).
  - Any extra kmods must match tag `ogc-45-<ostree.linux minus arch>`, following build.py's `{kernel_flavor}-{fedora_version}-{kernel_version}` pattern.
  - The template README says "The base and akmods images must use the same Fedora release and exact kernel version". It also notes that the standalone `*-nvidia` UB images were retired (ublue-os/main#927) ([README](https://github.com/ublue-os/image-template/blob/main/README.md)).
- **/var, /opt, /usr/local:**
  - Content in `/var` "acts like a Docker `VOLUME /var`", meaning it is applied only at install ([bootc-filesystem](https://github.com/bootc-dev/bootc/blob/main/docs/src/bootc-filesystem.7.md)).
  - Packages that write under `/opt` should be symlinked to `/var` ([bootc-building-images](https://github.com/bootc-dev/bootc/blob/main/docs/src/building/bootc-building-images.7.md)). The template's alternative is `rm /opt && mkdir /opt`.
  - Bazzite's `cleanup.sh` deletes `/var/*` except `cache`, recreates `/var/tmp` with mode 1777, and empties `/boot` and `/usr/lib/sysimage/libdnf5` ([cleanup.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/cleanup.sh)).
  - bootc prefers putting config in `/usr` rather than `/etc`, and using drop-in directories ([bootc-building-images](https://github.com/bootc-dev/bootc/blob/main/docs/src/building/bootc-building-images.7.md)).
- **Local testing:**
  - `just build`; `sudo just build` (builds in root storage so `bootc switch` can see it).
  - `just build-qcow2` (BIB, `--rootfs=btrfs`, `disk_config/disk.toml` with minsize 20 GiB).
  - `just run-vm-qcow2` (`docker.io/qemux/qemu` web console on `localhost:8006`, 4 CPU, 8 GB RAM, `TPM=Y`).
  - `just spawn-vm` (systemd-vmspawn) ([Justfile](https://github.com/ublue-os/image-template/blob/main/Justfile)).
- **Runner limits:** public-repo Linux runners have 4 CPUs, 16 GB RAM and a 14 GB SSD; private-repo runners have 2 CPUs and 8 GB RAM. Labels include `ubuntu-26.04` and `ubuntu-26.04-arm` ([GitHub docs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)). Bazzite frees space with `jlumbroso/free-disk-space`; the template uses `ublue-os/remove-unwanted-software`, last updated 2025-10.

---

## Recommendations for a two-variant repo

1. **Start from ublue-os/image-template.** It is supported by Universal Blue, actively updated, and matches Bazzite's own tooling. Use BlueBuild only if you prefer YAML recipes and accept no Universal Blue support and an archived ISO backend.
2. **Choose bases.**
   - SwayFX: `ghcr.io/ublue-os/bazzite:stable` (KDE desktop). Keep Plasma and add SwayFX from COPR `swayfx/swayfx` (enable → install → disable).
   - Bigscreen: `ghcr.io/ublue-os/bazzite-deck:stable` for the Steam Gaming Mode/HTPC behaviour, or `bazzite:stable` if Bigscreen should be the main session. Install Fedora's `plasma-bigscreen`, but first check the KDE version match (6.8.1 vs 6.8.3).
   - For NVIDIA, use `-nvidia-open` (or `-deck-nvidia`) as a third or fourth matrix leg rather than adding drivers yourself.
3. **Repo layout:**
   ```
   Containerfile            # ARG BASE_IMAGE / ARG VARIANT before FROM ${BASE_IMAGE}
   build_files/{build.sh,common.sh,swayfx.sh,bigscreen.sh}
   system_files/{shared,swayfx,bigscreen}/{etc,usr}
   disk_config/{disk.toml,iso-swayfx.toml,iso-bigscreen.toml}
   cosign.pub
   .github/workflows/{build.yml,build-disk.yml}
   ```
   - Edit the Justfile `build` recipe to fill `BUILD_ARGS` (`--build-arg BASE_IMAGE=… --build-arg VARIANT=…`).
   - Turn build.yml into `strategy.matrix.include: [{image: myos-swayfx, base: …/bazzite:stable, variant: swayfx}, {image: myos-bigscreen, base: …/bazzite-deck:stable, variant: bigscreen}]`.
   - Pass `${{ matrix.image }}` to every `just` call and set `fail-fast: false`.
4. **Branding and helpers:** in `common.sh`, rewrite `/usr/share/ublue-os/image-info.json` (`image-name`, `image-vendor`, `image-ref`) and `os-release`. Keep `base-image-name: kinoite`.
5. **Signing:**
   - One cosign key in `SIGNING_SECRET` and `cosign.pub` at the repo root.
   - Bake `/etc/pki/containers/myos.pub`, a `policy.json` `sigstoreSigned` entry for `ghcr.io/<you>`, and a `registries.d` file with `use-sigstore-attachments: true`.
   - Keep cosign v3 with `--new-bundle-format=false --use-signing-config=false`.
6. **Rechunking:** keep `just ostree-rechunk` (the default) or switch to chunkah, which matches Bazzite, but watch the 14 GB disk limit.
7. **ISOs:**
   - Preferred: follow Bazzite's Titanoboa pattern (live ISO with flatpaks; needs `/usr/lib/bootc-image-builder/iso.yaml`).
   - Alternative: migrate build-disk.yml to `osbuild/image-builder-action@v1` (`bootc-generic-iso`).
   - If you keep the template's BIB workflow, create per-variant `iso-*.toml` files that point at your images, because `iso.toml` is missing.
   - Host the ISOs on S3/R2 and sign them with `cosign sign-blob`.
8. **Install commands for users:**
   ```
   sudo bootc switch --enforce-container-sigpolicy ghcr.io/<you>/myos-swayfx:latest
   # or
   rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<you>/myos-bigscreen:latest
   ```
   Tell users not to rebase between the two variants if their bases differ (desktop vs deck), following Bazzite's DE-rebase warning.
