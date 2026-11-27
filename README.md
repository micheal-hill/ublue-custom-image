# ublue-custom-image

Two custom [Bazzite](https://bazzite.gg) images built from one repo with the
[Universal Blue image-template](https://github.com/ublue-os/image-template):

| Image | Variant | Base image | Meant for |
|---|---|---|---|
| `bazzite-swayfx-nvidia` | SwayFX desktop with the Noctalia shell. KDE Plasma stays as a fallback session. Adds the `nix` feature | `ghcr.io/ublue-os/bazzite-nvidia:stable` (NVIDIA LTS 580 driver) | Desktop/laptop with an older NVIDIA GPU (tested target: Dell Precision 5510, Quadro M1000M) |
| `bazzite-bigscreen` | KDE Plasma Bigscreen TV interface, with Steam Gaming Mode one step away | `ghcr.io/ublue-os/bazzite-deck:stable` (AMD/Intel) | Living-room HTPC |

The research behind the design is in [discovery-docs/bazzite-custom-images/](discovery-docs/bazzite-custom-images/).

## How it works

```
images.json ──► just build <image> ──► Containerfile (BASE_IMAGE, VARIANT, FEATURES build args)
                                          └─► build_files/build.sh
                                                ├─ copies system_files/shared/, system_files/<variant>/
                                                │  and system_files/features/<feature>/
                                                ├─ common.sh             (image identity + signing policy)
                                                ├─ variants/<variant>.sh  (desktop packages + session wiring)
                                                └─ features/<feature>.sh  (optional add-ons, e.g. nix)
```

- **`images.json` is the only place that pairs a base image with a variant and its features.** The
  GPU base (`bazzite`, `bazzite-nvidia`, `bazzite-deck`, `bazzite-deck-nvidia`, …) is independent
  of the variant's packages. Variant scripts never branch on GPU. They check that the base has what
  they need (for example, Bigscreen needs a deck base with `steamosctl`) and fail the build clearly
  if it doesn't.
- **Features** are optional add-ons that don't depend on the desktop, listed in an entry's
  `"features"` array. The only one so far is `nix`.
- CI builds one job per `images.json` entry (see `.github/workflows/build.yml`).

### Adding an image

Add an entry to `images.json`. For example, Bigscreen on a newer NVIDIA card:

```json
{ "name": "bazzite-bigscreen-nvidia", "base": "ghcr.io/ublue-os/bazzite-deck-nvidia:stable",
  "variant": "bigscreen", "description": "Bazzite HTPC with Plasma Bigscreen, NVIDIA open driver" }
```

## Building locally

The build needs `podman`, `just` and `jq`. All three come preinstalled on Bazzite and other
Universal Blue images.

```bash
just build bazzite-swayfx-nvidia
```
```bash
just build bazzite-bigscreen
```

From inside a distrobox whose host lacks `jq`, there are two options:
- Run `just` in the container and forward only `podman` to the host:
  ```bash
  mkdir -p ~/.local/hostbin && ln -sf /usr/bin/distrobox-host-exec ~/.local/hostbin/podman
  ```
  ```bash
  PATH="$HOME/.local/hostbin:$PATH" just build bazzite-bigscreen
  ```
- Or, on a NixOS host, run `nix-shell -p jq --run 'just build bazzite-bigscreen'`.

## What each variant changes

**`bazzite-swayfx-nvidia`** ([build_files/variants/swayfx.sh](build_files/variants/swayfx.sh)):
- **Packages:** one transaction installs:
  - SwayFX (from Terra) with Fedora's `sway-config-fedora` and `sway-systemd`
  - **Noctalia** (Fedora), the shell: bar, launcher, notifications, lock screen, idle, wallpaper,
    on-screen display, clipboard, and network, Bluetooth and power controls
  - **Ghostty** (Terra) as the terminal
  - **Displays Settings** (nwg-displays, Terra) for resolution, scale, rotation and screen layout.
    KDE's display settings can't drive sway, so its menu entry only shows in SwayFX. It won't
    start without a `~/.config/sway` folder, so a per-user tmpfiles rule creates an empty one at
    login. sway still uses the image's config until you add your own there
  - fuzzel as a fallback launcher; neovim; grim and slurp; the wlr portal (screen sharing)
  - fonts: Inter, Roboto, and the JetBrains Mono, FiraCode and Hack Nerd Fonts

  Terra is enabled for that transaction only and limited to the packages it supplies. Nothing
  duplicates what the KDE base or Noctalia already provides:
  - waybar, mako, rofi and the tray applets are left out (or not started), because Noctalia covers them.
  - KDE's own apps work in SwayFX too: Dolphin, Konsole, the Bluetooth and audio pages of System
    Settings, and the polkit password dialog. So there's no Nemo, blueman, pavucontrol or foot.
- **Default config ([system_files/swayfx/etc/sway/config](system_files/swayfx/etc/sway/config)):**
  - `exec noctalia`.
  - Vim-style bindings. `Mod+Space` opens the Noctalia launcher, `Mod+d` opens fuzzel,
    `Mod+Shift+Return` opens the terminal, and media and brightness keys go through Noctalia.
  - Tap-to-click with natural scrolling; Caps Lock as Escape, with Shift+Caps for Caps Lock.
  - Screenshots with grim and slurp, and swipe gestures to change workspace.

  It also starts KDE's polkit agent and pulls in Fedora's floating rules, XDG autostart and systemd
  session integration. It includes three files from `~/.config/sway/` when they exist: Noctalia's
  generated colours (`noctalia`), and the screen layout and workspace assignments that Displays
  Settings saves (`outputs`, `workspaces`).
- **Overriding:** add files to `~/.config/sway/config.d/`. A file with the same name as a vendor
  fragment replaces it, and an empty one turns it off, for example `80-swayfx.conf` (borders, gaps,
  corners, shadows, dim, animations) or `85-gaming.conf`. A full `~/.config/sway/config` replaces
  the whole default.
- **One look and one set of apps in both sessions:**
  - `QT_QPA_PLATFORMTHEME=kde` gives KDE apps under sway the same colours, icons, fonts and file
    dialogs as in Plasma.
  - The theme is Breeze. Change it once in KDE System Settings; that also sets the GTK theme.
  - Dolphin opens folders in both sessions.
  - Ghostty is SwayFX's terminal (`Mod+Shift+Return` and `xdg-terminal-exec`). Konsole stays KDE's
    terminal, and Dolphin's "Open Terminal" follows KDE's default-terminal setting.
  - Flatpak apps store secrets in KWallet. Fedora's sway portal config pointed at gnome-keyring,
    which isn't installed. Plasma Login Manager unlocks KWallet at login in every session.
- **New users** start with a Ghostty config in `/etc/skel` (FiraCode Nerd Font, 90% opacity).
- **Environment:** `SWAY_UNSUPPORTED_GPU=true` stops sway's NVIDIA warning. On this laptop the Intel
  iGPU drives every display, and the NVIDIA card only does render offload.
- **In a virtual machine only:**
  - `/etc/sway/environment` turns on wlroots' software cursor. QEMU's 3D-accelerated virtio-gpu
    otherwise shows the pointer upside down and offset
    ([QEMU issue 2315](https://gitlab.com/qemu-project/qemu/-/issues/2315)).
  - `sway-vm-autoresize.service` resizes the screen to follow the viewer window. The virtual GPU
    reports the new size, but wlroots ignores mode changes on a screen that stays connected.
  - Both check `systemd-detect-virt` and do nothing on real hardware.
- **Games on the NVIDIA GPU:** set a per-game Steam launch option of `switcherooctl launch %command%`.
  Don't set PRIME variables globally for Steam: its X11 update UI crashes under sway's Xwayland
  when they are set.
- **Login screen:** **SwayFX is the default session.** The image sets Plasma Login Manager's
  `[Greeter] PreselectedSession=sway.desktop` in `/usr/lib/plasmalogin/defaults.conf`. After a
  user's first login, the greeter remembers that user's last choice, so picking Plasma once keeps
  Plasma for them. KDE Plasma stays available as a fallback. To change the default, use *System
  Settings → Login Screen*, which writes `/etc/plasmalogin.conf`.
- **KWallet unlocks at login** in SwayFX too, as long as you log in with a password (autologin
  can't unlock it) and the wallet's password is your login password. In Plasma a systemd unit
  hands the login password over, but that unit is tied to the Plasma session. Its autostart
  entry is marked `X-systemd-skip`, which Fedora's sway session honours. So the sway config runs
  `/usr/libexec/pam_kwallet_init` itself.

**`bazzite-bigscreen`** ([build_files/variants/bigscreen.sh](build_files/variants/bigscreen.sh)):
- **Packages:** installs `plasma-bigscreen` at exactly the base's Plasma version. The build fails if
  the versions differ.
- **Session wiring:** points Bazzite's deck "desktop mode" at Bigscreen in three places:
  steamos-manager's `platform.toml`, `os-session-select`, and `bazzite-autologin`.
- **Boot target:** ships `/etc/bazzite/desktop_autologin`, so a fresh install autologins into
  Bigscreen instead of Gaming Mode.
  - Change the default with `ujust`'s deck-session recipes, or
    `steamosctl set-default-login-mode game|desktop`.
  - Note: `bazzite-autologin` only writes `/etc/sddm.conf.d/zz-holo-autologin.conf` when it is
    missing. A machine *rebased* from stock `bazzite-deck` will likely keep booting to Gaming Mode
    until you switch the default login mode as above. This hasn't been tested yet.
- **Steam tile:** switches to Gaming Mode instead of opening the desktop Steam client. The
  OpenGamepadUI launcher is removed, because Bigscreen ignores hidden launchers.
- **Audio and browser:** HDMI/DisplayPort audio is preferred as the default output. Links open in
  Bazzite's Firefox Flatpak, because Aura isn't packaged for Fedora.

## Features

**`nix`** ([build_files/features/nix.sh](build_files/features/nix.sh)) adds the Nix package
manager in multi-user daemon mode, for user environments with home-manager, devenv and nix-direnv.
- Uses Fedora's own `nix` and `nix-daemon` packages. Flakes and `nix-command` are on, and members of
  `wheel` are trusted users, so they can use extra binary caches such as devenv's.
- **Where the store lives:** `/` is read-only on bootc and Nix refuses a symlinked `/nix`, so the
  store lives in `/var/nix` and is bind-mounted onto `/nix` early in boot (`nix.mount`). It sits in
  `/var`, so image updates and rollbacks don't touch it.
- **SELinux labels:** Fedora's policy has no labels for `/nix`, and without them systemd can't create
  the daemon socket. The image adds file-context rules:
  - the store is labelled like `/usr`,
  - `/nix/var` like `/var`,
  - the socket directory like `/run`,
  - and `/var/nix` gets the same labels as `/nix`.

  tmpfiles fixes the top-level directories' labels on every boot. A store that was filled before
  these rules existed needs a one-off `sudo restorecon -R /var/nix`.
- **First run:** open a new login shell (the daemon profile scripts set `PATH`), then:
  ```bash
  nix run nixpkgs#hello
  ```
  ```bash
  nix run home-manager/release-26.05 -- init --switch
  ```
- **home-manager on a non-NixOS system:**
  - Set `targets.genericLinux.enable = true;`.
  - For Nix-installed fonts, set `fonts.fontconfig.enable = true;`.
  - Leave out what the image already ships (for example Noctalia and fish), so you don't end up
    with two copies.
  - Prefer Flatpak or image packages for GUI apps. Nix-built OpenGL/Vulkan apps can't find the
    system GPU drivers without extra setup (see home-manager's `targets.genericLinux.gpu`).
- **Distrobox:** containers only see the store if they are created with `--volume /nix:/nix:ro`.

## Testing in a VM (virt-manager)

bootc-image-builder turns a locally built image (from `just build <image>`) into a VM disk or an
installer ISO. It needs rootful, privileged podman, so these recipes copy your image into root's
podman storage and **ask for your sudo password**. Run them on the host, in a terminal, from this
folder, **without** a `sudo` prefix. They need only `just`, `podman` and `sudo`; `jq` isn't required.

```bash
just build-qcow2 bazzite-bigscreen   # disk image → output/bazzite-bigscreen/qcow2/disk.qcow2
```
```bash
just build-iso bazzite-bigscreen     # installer → output/bazzite-bigscreen/bootiso/install.iso
```

- **qcow2:** `build-qcow2` first asks for a **VM login username and password**. A
  bootc-image-builder disk has no user account, and Bazzite has no first-run wizard. The answers go
  into a temporary, owner-only, gitignored config that is deleted when the build finishes. Use a
  throwaway password; it only exists inside that VM. On `bazzite-bigscreen`, this user becomes the
  autologin user.
- **ISO:** the installer asks for the user during installation.
- **Disk space:** each disk image takes roughly 10–15 GB, and copying an image into root's storage
  takes another ~12 GB. `just vm` uploads one more copy into libvirt's pool. Build one image at a
  time. Between them, run `just clean` and `sudo podman rmi localhost/<image>`.
- **One password prompt:** copying the image into root's storage, the build and the copy into
  `output/` all run under one `sudo`. Each of them can take longer than sudo's 5-minute
  password cache, so separate `sudo` calls would ask again partway through.
- **Interrupted builds** can leave `_build-bib.*` or `_build_podman_scp.*` folders holding
  root-owned files. Remove them with `sudo rm -rf _build-bib.* _build_podman_scp.*`.

**Create and start the VM** from the qcow2 (no sudo):
```bash
just vm bazzite-swayfx-nvidia
```
- The recipe uploads the disk into libvirt's default storage pool (`/var/lib/libvirt/images`)
  through libvirt itself, and starts libvirt's `default` network if it's stopped.
- It then defines and boots `<image>-test` on `qemu:///system` with the settings below. That
  includes OpenGL on the first non-NVIDIA render node, with UEFI and Secure Boot off.
- Open virt-manager and double-click the VM to see its console.
- **To start over with a new disk:** remove the old VM with
  `virsh -c qemu:///system undefine <image>-test --nvram --remove-all-storage` (after a
  `virsh destroy` if it's running), then rebuild the qcow2 and run `just vm` again.

**virt-manager settings,** which `just vm` applies for you, or for setting up a VM by hand:
- **qcow2:** *New VM → Import existing disk image*, pointing at `disk.qcow2`.
- **ISO:** *Local install media*, with a new empty 60 GB disk.
- **Firmware:** UEFI (OVMF), without Secure Boot, because the image's kernel is signed with
  Universal Blue's key. Set this under *Customize configuration before install → Overview*.
- **CPU and RAM:** 4+ vCPUs and 8 GB RAM.
- **Video:** Virtio, with *3D acceleration* ticked.
- **Display:** Spice, with *Listen type: None* and *OpenGL* ticked.
- **Screen follows the window:** in the VM console window, tick *View → Scale Display → Auto resize
  VM with window*. This is a virt-manager setting, not part of the VM.

### What a VM can and can't show

| | Testable in a VM | Needs real hardware |
|---|---|---|
| `bazzite-swayfx-nvidia` | SwayFX listed at login and starts. Noctalia's bar and launcher (`Mod+Space`); corners and shadows render; the pointer is the right way up, and the screen follows the window size; Displays Settings changes the resolution and keeps it after logging out and back in; Ghostty; Dolphin themed like in Plasma; a KDE password dialog (for example from `pkexec true`); portals; KDE fallback session (no second Bluetooth tray icon); `ujust`. Nix: `systemctl status nix.mount nix-daemon.socket`, then `nix run nixpkgs#hello`. Secrets: a Flatpak app that signs in should prompt for KWallet once | NVIDIA PRIME offload. The NVIDIA kernel modules won't load in a VM; that is expected. |
| `bazzite-bigscreen` | Autologin into Bigscreen; navigation with keyboard (or a USB-passthrough controller); the Steam tile's behaviour | Steam Gaming Mode (gamescope is unreliable in VMs), HDMI audio, HDMI-CEC remotes |

- After an ISO install, check whether Bazzite's Flatpaks (the browser) were installed.
- Inside KVM guests, Fedora's `start-sway` sets `WLR_RENDERER=pixman` (wlroots' software renderer)
  and legacy KMS. SwayFX ignores the renderer setting and always draws with OpenGL, through virgl
  in the VM. Hence the software cursor above.

## Publishing and installing

**CI** ([.github/workflows/build.yml](.github/workflows/build.yml)) builds every `images.json` entry
in its own job.
- **When it runs:** on each push to `main` (but not for changes only to READMEs or
  `discovery-docs/`), every day at 18:24 UTC to pick up Bazzite updates, and on demand from
  *Actions → Build container image → Run workflow*. Pull requests are built but never published.
- **On `main`, each image is:**
  - rechunked for smaller updates with [chunkah](https://github.com/coreos/chunkah), after CI checks
    the chunkah image's signature. Unlike the template's rpm-ostree rechunker, chunkah keeps the
    image's labels (version, source commit, description), so `bootc status` shows the version;
  - pushed to `ghcr.io/micheal-hill/<image>` with the tags `latest`, `latest-<date>`, `<date>`, and
    variants with the commit SHA;
  - signed with cosign. The private key is the `SIGNING_SECRET` secret of the `publish`
    environment, which only the `main` branch can use, so pull requests and other branches build
    without it. The public key is [keys/cosign.pub](keys/cosign.pub).
- **Images built in CI trust that key for updates.** `common.sh` installs it with a
  `sigstoreSigned` policy for `ghcr.io/micheal-hill`. Local builds (vendor `localhost`) skip this.
- **After the first run:** open each package under the GitHub profile's *Packages* tab. If its
  visibility is *Private*, change it to *Public* in *Package settings*, so machines can pull it
  without logging in.

**Check a published image's signature:**
```bash
cosign verify --key keys/cosign.pub ghcr.io/micheal-hill/bazzite-swayfx-nvidia:latest
```

**Install on a machine** (not yet tested on hardware):
1. Install stock Bazzite with the matching base. For `bazzite-swayfx-nvidia`, use the NVIDIA image
   for GTX 9xx/10xx-era cards (`bazzite-nvidia`). For `bazzite-bigscreen`, use the HTPC/handheld
   image (`bazzite-deck`). **On the laptop this replaces NixOS: back up first.**
2. Switch to this image and reboot. Stock Bazzite doesn't know this repo's key yet, so this first
   switch can't check the signature:
   ```bash
   sudo bootc switch ghcr.io/micheal-hill/bazzite-swayfx-nvidia:latest
   ```
3. Once booted into it, switch again with signature checks on. Every later update is then
   verified:
   ```bash
   sudo bootc switch --enforce-container-sigpolicy ghcr.io/micheal-hill/bazzite-swayfx-nvidia:latest
   ```
4. `bootc status` should show the image. Updates then arrive through Bazzite's usual update
   service, or with `ujust update`.

**Alternatively, build an installer** that switches to the published image after installing:
```bash
GITHUB_REPOSITORY_OWNER=micheal-hill just build-iso bazzite-swayfx-nvidia
```
Without that variable, `build-iso` makes a local test installer that stays on the image it was
built from. With it, run step 3 after the first update has installed the published image. For a
USB stick, the live installer below handles more for you.

### USB installer (live ISO)

`just build-live-iso` makes a bootable USB installer the way Bazzite makes its own ISOs: Bazzite's
installer recipe plus [Titanoboa](https://github.com/ublue-os/titanoboa). Both are git submodules
in [live_iso/](live_iso/UPSTREAM.md), pinned to exact commits; the recipe checks them out on first
use (about 140 MB). So far it's only been tried with `bazzite-swayfx-nvidia`.

```bash
just build-live-iso bazzite-swayfx-nvidia
```

- **No sudo:** it runs with your rootless podman. Run it on the host, from this folder.
- **Needs:** about 50 GB free, a network connection (about 10 GB of downloads: stock Bazzite, the
  published image and the Flatpaks), and an hour or more. It stops early if there isn't enough
  space.
- **Output** in `output/<image>/live-iso/`:
  - `<image>-live.iso`, probably over 10 GB, so use a 16 GB stick;
  - its `.sha256`;
  - `build-info.txt`, listing the image digests, this repo's commit and the Flatpak versions it used;
  - `build.log`.

  The ~25 GB build container (`<image>-live-root`) is deleted afterwards; `KEEP_LIVE_ROOT=1`
  keeps it.

**What's on the stick:**
- The live session is stock Bazzite's KDE desktop, not this image. It's for installing and
  troubleshooting, not for trying SwayFX.
- The installer is Anaconda. It installs `ghcr.io/micheal-hill/<image>:latest` from a copy on the
  stick, so installing needs no network.
- The build only accepts that copy if it's signed with [keys/cosign.pub](keys/cosign.pub).
- After installing, the system already checks signatures on updates, so the two `bootc switch`
  steps above aren't needed.
- Bazzite's KDE Flatpaks (Firefox, Okular, Gwenview, Flatseal, ProtonPlus and others) are on the
  stick and copied to the new system.
- The stick boots with Secure Boot on: the live session uses Fedora's signed kernel.
- The installer still says "Bazzite" in places.

**Write the stick** with Fedora Media Writer ("Select .iso file"), or with `dd`, replacing
`/dev/sdX` with the stick (`lsblk` shows it):
```bash
sudo dd if=output/bazzite-swayfx-nvidia/live-iso/bazzite-swayfx-nvidia-live.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

**Install:**
1. Boot from the stick and pick *Install bazzite-swayfx-nvidia*.
2. Install from the welcome dialog.
3. With Secure Boot on, the first reboot shows a blue MokManager screen. Choose *Enroll MOK* and
   enter the password `universalblue` to trust Universal Blue's kernel key.
4. `bootc status` should then show the signed `ghcr.io/micheal-hill/<image>:latest`.

**Reproducing a build:**
- `build-info.txt` records what went in.
- The upstream code and the Fedora image that builds the ISO are pinned.
- Stock Bazzite's `stable` tag, the published image's `latest` tag, Fedora packages and Flathub
  apps change over time. Rebuilding later gives a newer stick.

### One-time setup on the Dell Precision 5510

These steps are machine-specific, so they're done on the laptop rather than baked into the image.
Both persist across image updates.
- **Kernel arguments**, from the nixos-hardware profile for this model:
  - `i915.enable_psr=0` stops panel flicker.
  - `mem_sleep_default=deep` makes suspend use S3 sleep.
  - `acpi_rev_override=1` is the Dell ACPI workaround for this model.

  Reboot after running:
  ```bash
  sudo rpm-ostree kargs --append-if-missing=i915.enable_psr=0 --append-if-missing=mem_sleep_default=deep --append-if-missing=acpi_rev_override=1
  ```
- **Optional, log straight into SwayFX:** in `/etc/plasmalogin.conf`, under `[Autologin]`, set
  `User=<your user>` and `Session=sway.desktop`. Without a typed password, KWallet stays
  locked until something first asks for it.
- **Virtual machines:** run `ujust setup-virtualization`, which enables libvirtd, installs the
  virt-manager Flatpak and sets the needed kernel arguments.
