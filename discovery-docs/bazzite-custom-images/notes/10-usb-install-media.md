# Installing from a USB stick (2026-11-25)

How to put `bazzite-swayfx-nvidia` or `bazzite-bigscreen` on a machine from a USB stick. This
builds on the ISO tooling in `01-build-tooling.md` §4, which was checked on 2026-11-22.

## Options

| Option | Effort | Secure Boot | Flatpaks | Where the ISO lives |
|---|---|---|---|---|
| Official Bazzite ISO, then `bootc switch` (README "Install on a machine") | none | the installer queues the MOK key; confirm it in MokManager after reboot | Bazzite's normal setup | Bazzite's download site |
| `just build-iso` (bootc-image-builder `anaconda-iso`, already in this repo) | local sudo build, plenty of free disk | not enrolled; see below | first-boot service (unverified) | your disk |
| ISO built in CI | a new workflow plus hosting | as above, or as Bazzite does | as above | needs S3/R2: release assets must be under 2 GiB |
| Titanoboa live ISO, as Bazzite builds it | an installer payload build (`installer/` in Bazzite) | the `mokutil --import` post-script queues it | installed into the ISO | as above |

## Findings

- **Secure Boot** (https://docs.bazzite.gg/General/Installation_Guide/install-guide/):
  - Universal Blue's key must be enrolled before Bazzite's kernel boots with Secure Boot on.
  - Bazzite's own installer queues it with `mokutil --import`, using the password `universalblue`.
    The user then picks "Enroll MOK" on the blue MokManager screen at the next boot.
  - Otherwise: turn Secure Boot off, run `ujust enroll-secure-boot-key` (password
    `universalblue`), reboot through MokManager, then turn Secure Boot back on.
  - The key is in our image at `/etc/pki/akmods/certs/akmods-ublue.der`.
  - Our `iso.toml.in` kickstart does not enroll it.
- **Flatpaks:** our image ships `bazzite-flatpak-manager.service`, which is enabled.
  - Titanoboa's hook turns it off in the live environment, which suggests it's what installs
    Bazzite's Flatpaks on a normal first boot.
  - I haven't read what it does, and it presumably needs a network connection.
- **bootc-image-builder:**
  - osbuild is deprecating the container and CLI "in favor of the unified image-builder CLI"
    (https://osbuild.org/docs/bootc/deprecation-notice/).
  - The Anaconda ISO type still works, but is planned for removal in RHEL 11.
  - The template's `build-disk.yml` still uses `osbuild/bootc-image-builder-action@8661cd3` with
    `anaconda-iso` and `--use-librepo=True`. It uploads to Actions artifacts
    (`retention-days: 0`) or to S3 with rclone.
  - Which kernel the `anaconda-iso` installer boots, and whether that works with Secure Boot on,
    isn't documented. Test it before relying on it.
- **Titanoboa** (https://github.com/ublue-os/titanoboa, last commit 2026-05-19, `5c457c3`):
  - The image needs `/usr/lib/bootc-image-builder/iso.yaml` (a label and GRUB2 entries). Ours
    doesn't have one.
  - Bazzite's `installer/build.sh` turns the image into a live payload: it installs Flatpaks and
    `dracut-live`, regenerates the initramfs, adds `anaconda-live`, and writes `iso.yaml`.
  - Its Anaconda post-scripts run `bootc switch --mutate-in-place`, install the Flatpaks and import
    the MOK key.
- **GitHub hosting:**
  - Each release asset must be under 2 GiB, so an ISO can't go in a release.
  - Actions artifacts work, but the docs I read didn't give a per-artifact limit, a default
    retention or the sign-in rules.
  - Bazzite publishes its ISOs to Cloudflare R2.
- **Writing the stick:** Bazzite recommends Fedora Media Writer and a stick of 16 GB or more. Rufus
  and Ventoy also work; Ventoy needs extra steps for Secure Boot.

## Option 4 in detail: Bazzite's live ISO (sources read 2026-11-25)

**Sources:**
- Bazzite `installer/`: `Containerfile`, `build.sh`, `titanoboa_hook_preinitramfs.sh`,
  `titanoboa_hook_postrootfs.sh`, `iso.yaml`, `kde_flatpaks/flatpaks`, `system_files/`
- Bazzite `.github/workflows/build_iso.yml`
- Titanoboa `action.yml` and README. Last commit `5c457c3` (2026-05-19); the previous one was
  2026-01-04.

**How Bazzite builds its ISO:**

1. `installer/Containerfile` starts `FROM $BASE_IMAGE` and runs `build.sh` with three build args:
   - `BASE_IMAGE`: the live system you boot from the stick. Bazzite always uses the plain desktop
     image here. Its workflow strips `-deck`, `-nvidia`, `-nvidia-open` and `-dx` from the name;
     the comment says "We need this as we use the desktop image as the runtime for the livecds".
   - `INSTALL_IMAGE_PAYLOAD`: the image Anaconda installs. It's pulled into the live system's own
     container storage, so installing doesn't need the network.
   - `FLATPAK_DIR_SHORTNAME`: `kde_flatpaks` or `gnome_flatpaks`, the list of Flatpaks to bake in.
2. `build.sh`:
   - installs the Flatpaks from Flathub into the live system (the KDE list: Firefox, Gwenview,
     Okular, KCalc, Haruna, Kontainer, Flatseal, Protontricks, Warehouse, ProtonPlus, Firmware,
     plus the OBS, MangoHud and vkBasalt runtimes);
   - pulls the payload;
   - runs the pre-initramfs hook;
   - installs `dracut-live` and rebuilds the initramfs with `dmsquash-live`;
   - installs `livesys-scripts` (KDE session);
   - runs the post-rootfs hook;
   - makes a large tmpfs for `/var/tmp` (ostree needs the space) and mounts `/var/lib/flatpak`
     read-only;
   - copies `iso.yaml` to `/usr/lib/bootc-image-builder/iso.yaml`.
3. **Pre-initramfs hook:** swaps Bazzite's kernel for Fedora's signed `kernel` from the fedora and
   updates repos, "because we want the initramfs to use a signed kernel for secureboot". So the
   stick boots with Secure Boot on. The installed system still gets the payload's own kernel.
4. **Post-rootfs hook:**
   - Installs `anaconda-live` and Firefox.
   - Writes the kickstart defaults:
     - a BitLocker warning;
     - `ostreecontainer --url=$imageref:$imagetag --transport=containers-storage --no-signature-verification`;
     - a post-script running
       `bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry $imageref:$imagetag`,
       so updates are signature-checked from the first boot;
     - post-scripts that install the Flatpaks and restore SELinux labels;
     - `mokutil --import /usr/share/ublue-os/sb_pubkey.der` with the password `universalblue`
       (skipped on non-EFI systems and Valve hardware), plus a dialog pointing to the docs.
   - Turns off services the live session shouldn't run, including the update timers and the
     Flatpak managers.
   - For payloads with `-nvidia` in the name, uses nouveau in the live session.
   - Removes Steam, Lutris, Bazaar and Waydroid from the live session.
   - `$imageref` is found with `podman images ... 'bazzite*'`.
5. **The workflow (`ubuntu-latest`):**
   - Frees disk space, then puts podman storage on a 110 GB sparse btrfs loopback with
     `compress-force=zstd:2`.
   - Runs `sudo podman build --cap-add sys_admin --security-opt label=disable --build-arg …`,
     then `ublue-os/titanoboa@5c457c3` with `image-ref: localhost/payload:latest`.
   - Writes a sha256 checksum, signs the ISO with `cosign sign-blob --key env://SIGNING_KEY`, and
     attests build provenance.
   - Uploads to R2 from `main`, or to artifacts with `retention-days: 1` from testing.
6. **Titanoboa:** the action runs `main.sh` with `TITANOBOA_CTR_IMAGE` set to the image and returns
   `iso-dest`. Its README calls the project "an experiment", but Bazzite's official ISOs come from it.

**Fit with this repo:**
- Our image names start with `bazzite-`, so the `'bazzite*'` lookup finds our payload. The
  `-nvidia` check applies to `bazzite-swayfx-nvidia`.
- Our images trust our cosign key, so `--enforce-container-sigpolicy` works after installing.
- So Bazzite's `installer/` could run almost unchanged:
  - `BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable` (the live session is stock Bazzite KDE, not SwayFX)
  - `INSTALL_IMAGE_PAYLOAD=ghcr.io/micheal-hill/<image>:latest`
  - `FLATPAK_DIR_SHORTNAME=kde_flatpaks`
- Bazzite-specific but harmless: the boot menu says "Launch Bazzite Installer", plus the Anaconda
  profile, the wallpaper and the `bazzite_xboot` boot-partition label.
- Two ways to bring it in:
  - copy `installer/` into this repo (Apache-2.0, with credit), which lets us change the branding
    and Flatpak list but means syncing by hand;
  - check out Bazzite at a pinned commit in CI, which needs no copy but ties us to its naming
    assumptions.
- A local build needs a lot of free disk: two ~12 GB images, the Flatpaks, the built payload
  image and the ISO. (Later, the user chose a local rootless build; see below.)
- Hosting: ISOs are too big for release assets (each must be under 2 GiB). Short-lived Actions
  artifacts from a manual run are enough for a couple of sticks.
- **Unverified:**
  - build time and ISO size for our payloads;
  - whether `bazzite-bigscreen`'s autologin picks up the user Anaconda creates.

## Scripting the live ISO locally (bazzite-swayfx-nvidia first)

The user chose a local, scripted build, with no CI or hosting, because installs are rare.

**How Titanoboa runs** (at `5c457c3`):
- `main.sh` runs
  `sudo podman run --rm -i --cap-add sys_admin --security-opt label=disable --mount type=image,source=$IMAGE,dst=/rootfs -v $OUT:/output quay.io/fedora/fedora:latest /src/build_iso.sh`.
- `build_iso.sh` installs `squashfs-tools xorriso yq mtools dosfstools` with dnf. It then builds
  the stick's contents:
  - `mksquashfs /rootfs … -e sysroot -e ostree -comp zstd -Xcompression-level 19`;
  - the kernel and initramfs copied to `/images/pxeboot`;
  - a GRUB config generated from `iso.yaml`;
  - a 100 MB FAT EFI partition.

  Finally `xorriso` writes `/output/<label>.iso`.
- No host packages are needed beyond podman and sudo.

**Host on 2026-11-25:**
- podman 5.8.9, `just`, `sudo`, `git` and `curl`. No `cosign`, `skopeo` or `jq`, so the recipe
  can't use `jq` on the host.
- `/`, `/tmp` and `/var/tmp` are all on one filesystem, which was too full at first. Removing this
  project's rootless podman images freed ~34 GB.

**Disk estimate** (unverified), all in root's podman storage:

| Stage | Size |
|---|---|
| `bazzite:stable` | ~12 GB |
| The build step's layer: the payload (~13 GB), Flatpaks and dnf | ~17 GB |
| Committing that layer (temporary) | ~17 GB |
| The squashfs inside the Fedora builder container | ~11–13 GB |
| The ISO | ~11–13 GB |

The peak is about 55–60 GB, and the ISO probably needs a 16 GB stick.

**Pins to record for reproducibility:**

| Input | Pin |
|---|---|
| Bazzite `installer/` | commit `eea6eb03e610` (2026-11-13) |
| Titanoboa | `5c457c3` |
| Builder container | `quay.io/fedora/fedora:45`, the same digest as `latest` today: `sha256:92837d48…` |
| `BASE_IMAGE` (stock Bazzite) | resolve the digest at build time; `build.sh` only checks the name for `-gnome` |

- The payload has to be pulled **by tag**. The post-install `bootc switch` reads `$imageref:$imagetag`
  from `podman images`, and that tag is what the installed system updates from. Record which digest
  was pulled.
- dnf packages and Flathub apps still float. Record the Flatpak versions from the built live image.

**Verifying the payload:** Anaconda installs it with `--no-signature-verification`. After that,
updates are checked, because the `bootc switch` uses `--enforce-container-sigpolicy`. Two ways to
close that first gap:
- pull and verify the payload in root's storage first (cosign in a pinned container, or a podman
  pull with a policy file), then mount root's storage at `/usr/lib/containers/storage`. `build.sh`
  then copies that exact image instead of pulling, at the cost of another ~13 GB;
- verify the digest that ended up inside the live image against GHCR after the build.

**Chosen (2026-11-25):** `live_iso/trust-payload.sh` runs in the build before Bazzite's `build.sh`.
It adds our `sigstoreSigned` policy for `ghcr.io/<owner>` (the same as `common.sh`) to the live
image's `/etc/containers/policy.json`, plus a registries.d `use-sigstore-attachments` entry. Then
`build.sh`'s own `podman pull` enforces the signature, with no extra tools or disk.
- **Negative test:** with Universal Blue's key standing in for ours, the pull failed straight away
  ("Source image rejected: cryptographic signature verification failed: invalid signature when
  validating ASN.1 encoded signature").
- So the policy is enforced, and the signature is found on GHCR.

**Bringing in Bazzite's installer:** copying `installer/` into the repo means the changes go through
reviewed pull requests, and upstream updates show up as diffs. Fetching it at a pinned commit avoids
the copy. Our own changes would be small: `iso.yaml` (label and entry names; the label must match
`root=live:CDLABEL=`), and optionally the Flatpak list.

**Sudo:** run the whole build inside one sudo call, as `_build-bib` does. `timestamp_timeout` is
5 minutes, and a second prompt partway through a long step times out.

**Avoiding the sudo prompt partway through a recipe** (2026-11-25):
- **Rootless podman, with no sudo at all.**
  - The host is ready for it: a 100000-ID range for the user in `/etc/subuid` and `/etc/subgid`,
    `max_user_namespaces` is 127549, `/dev/fuse` is mode 0666, and rootless podman uses overlay
    (graph root `~/.local/share/containers/storage`).
  - Titanoboa's step should work rootless: an image mount, `mksquashfs -all-root` and `xorriso`.
  - Untested rootless in Bazzite's `build.sh`:
    - `mount -o remount,rw /proc/sys`;
    - Flatpak's bwrap sandbox inside the build;
    - `podman pull` of the payload inside a build step, which puts container storage inside the
      build's own overlay.

    Bazzite only runs this rootful (`sudo podman build`).
  - bootc-image-builder (`build-qcow2`, `build-iso`) needs rootful podman, so this doesn't apply to it.
  - **Probe results (2026-11-25):** run with rootless `podman build` on the host, using Bazzite's
    options `--cap-add sys_admin --security-opt label=disable`, on `ghcr.io/ublue-os/bazzite:stable`
    `45.20261123.1` (`sha256:e60b3eb0…`).

    | Step | Result |
    |---|---|
    | `mount -o remount,rw /proc/sys` (`/proc/sys` is a mount point there) | OK |
    | `flatpak install` of `runtime/org.freedesktop.Platform.VulkanLayer.MangoHud/x86_64/25.08` from Bazzite's list | OK |
    | Nested `podman pull quay.io/fedora/fedora-minimal:45` (inner storage: overlay at `/var/lib/containers/storage`) | OK |
    | `dnf install dracut-live`, then `dracut --no-hostonly --add "dmsquash-live dmsquash-live-autooverlay"` (296 MB initramfs) | OK |
    | Flatpak's trigger sandbox | **fails** unless the build also gets `--cap-add net_admin` |

    The trigger sandbox details:
    - Flatpak runs `.trigger` scripts with
      `bwrap --unshare-ipc --unshare-net --unshare-pid --ro-bind / / --proc /proc --dev /dev --bind <basedir> <basedir>`
      (`flatpak_dir_run_triggers` in `common/flatpak-dir.c`).
    - It doesn't check bwrap's exit status. A failed trigger is silently skipped; the install still
      succeeds, but the desktop, MIME and icon caches in `/var/lib/flatpak/exports` aren't refreshed.
    - Without `net_admin`: `bwrap: loopback: Failed RTM_NEWADDR: No child processes`. bwrap runs as
      (container) root, so it doesn't create its own user namespace, and it can't configure loopback
      in the new network namespace.
    - With `--cap-add net_admin` the exact trigger command succeeds. `--security-opt unmask=ALL`
      isn't needed.
    - Bazzite's rootful CI build also has no `net_admin`, so its triggers probably fail the same
      way. That's an inference, not tested.
    - A broader `bwrap --unshare-all --proc /proc` failed with "Can't mount proc on /proc:
      Operation not permitted". Flatpak doesn't use those options.
  - **Full builds of `just build-live-iso bazzite-swayfx-nvidia` (2026-11-25, rootless, on the host):**
    - **Run 1 (`podman build`):** all of `build.sh` succeeded in 17 minutes: the signature-checked
      payload pull, the Flatpaks, the kernel swap, Anaconda and dracut. Committing the step then
      failed: "writing blob: storing blob to file /var/tmp/container_images_storage…/1: no space
      left on device", with 54 GB free and stock Bazzite already pulled.
      - A commit writes the container's changes out as an uncompressed tar blob, then unpacks it
        into a new layer. So it briefly needs the container's changes, the blob and the new layer:
        about three copies.
      - The layer must have been over ~27 GB. Bazzite's Flatpak list pulls in two Freedesktop
        runtimes (25.08 and 26.08), GNOME Platform 49, 50 and 51, KDE 6.11, codecs, and GL and
        VAAPI extensions, on top of the ~13 GB payload.
      - Flatpak also installed `GL.nvidia-580-178-04` and `GL32.nvidia-580-178-04`, matching the
        build host's NVIDIA driver.
    - **Fix:** no `podman build`. `live_iso/build-live-root.sh` runs `build.sh` in a plain
      container (`podman run --name <image>-live-root`). Titanoboa's step then reads that container
      through `podman unshare` + `podman mount`, passed as `-v <mount>:/rootfs:ro`; a small test
      confirmed this works rootless. `FLATPAK_GL_DRIVERS=default` stops the host-specific NVIDIA
      extensions.
    - **Run 2:** succeeded in 16 minutes: 10 for the live system, 6 for `mksquashfs` (zstd -19)
      and `xorriso`.
      - The ISO is 8.8 GiB (9,447,417,856 bytes), so a 16 GB stick is enough.
      - Free space went from 54 GB to 45 GB, ISO included, once the container was removed.
      - The log has no "Error running trigger" lines. One Fedora mirror connection reset was
        retried.
      - The payload digest was recorded:
        `sha256:5033e821e4ccdbdd4b9e2329a54b7ce2a1b8e8338fcc0e054763524d6a49e095`.
- **`sudo just <recipe>`.** The password prompt comes first, before anything starts, and the rest
  runs as root with no further prompts.
  - Caveats:
    - sudo might not find `just` in `~/.nix-profile/bin` if `secure_path` is set; the fallback is
      `sudo "$(command -v just)" …`. Not checked: `host-config/` was empty (not mounted) on
      2026-11-25.
    - Files the recipe writes are owned by root unless it `chown`s them back to
      `$SUDO_UID:$SUDO_GID`.
    - `git` run as root in the user's checkout fails its "dubious ownership" check.
  - The recipe should refuse to run unless it's root.
- `run0` (systemd) is also installed. It behaves like `sudo` here, with a polkit prompt.
- Lengthening `timestamp_timeout` or `passwd_timeout` would be a host config change, and the
  prompt would still come partway through.

**Testing:** boot the ISO in a UEFI VM, optionally with a Secure Boot OVMF to check signed boot and
the MOK request, and install to an empty disk. Then check:
- `bootc status` shows a signed `ghcr.io/micheal-hill/bazzite-swayfx-nvidia:latest`;
- the SwayFX session starts;
- the Flatpaks are present;
- the kernel is Bazzite's.

## State on 2026-11-25

- **The `build-iso` path has never been tested,** in a VM or on hardware.
- It builds from the local image (`localhost/<image>`), not the published one.
- With `GITHUB_REPOSITORY_OWNER` set, the kickstart switches to `ghcr.io/<owner>/<image>:latest`
  after installing, without signature checks. `--enforce-container-sigpolicy` is a later manual
  step.
- A local bootc-image-builder ISO build needs the image in root's podman storage (~12 GB), plus
  bootc-image-builder's scratch space and output.
