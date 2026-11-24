<!-- Research notes gathered 2026-11-22 by a research subagent (web + GitHub/registry APIs). -->

# SwayFX on a Bazzite-derived bootc image: research notes, as of 2026-11-22

Method: the GitHub REST API (until it hit its anonymous rate limit), GHCR, quay.io and Fedora mdapi APIs, and parsed COPR and Terra repodata. `gh` and `dnf` are not installed on this host, so they were not used. Anubis blocked parts of src.fedoraproject.org and copr.fedorainfracloud.org; its raw files and API endpoints still worked.

---

## 1. SwayFX packaging

### Takeaway
SwayFX is **not in official Fedora**. It ships from two places. Terra has **swayfx 0.6.1**, and Bazzite already configures Terra. The `swayfx/swayfx` COPR has 0.6. Both RPMs declare `Provides: sway = 1.12` and `Conflicts: sway`, with no `Obsoletes`. Upstream 0.6.x is rebased on **sway 1.12.0**, wlroots 0.20 and scenefx 0.5.

### Cited Findings
- The upstream repo moved to **github.com/wlrfx/swayfx** (the API returns `full_name: wlrfx/swayfx`, last push 2026-11-22, 185 open issues). — [API](https://api.github.com/repos/wlrfx/swayfx)
- **0.6.1**, published 2026-11-13, is a bugfix release: animation timing, shadows disabled when there are no gaps, crash fixes. — [releases](https://github.com/wlrfx/swayfx/releases)
- **0.6**, published 2026-08-05, is a "rebase off of sway 1.12.0" that adds animations (`animation_duration_ms`) and switches to "wlroots-20 and scenefx-0.5". 0.5.3 (2025-06-28) was based on sway 1.11.0. — [releases](https://github.com/wlrfx/swayfx/releases)
- **scenefx 0.5** was released 2026-07-08 on wlroots 0.20. 0.4.1 (2025-06-24) was on wlroots 0.19. — [scenefx releases](https://github.com/wlrfx/scenefx/releases)
- swayfx is not in official Fedora. packages.fedoraproject.org/pkgs/swayfx returns 404, and mdapi f45 has no swayfx. — [mdapi f45](https://mdapi.fedoraproject.org/f45/pkg/swayfx)
- Fedora's own sway is 1.12-2 in F45 and Rawhide, 1.11-3 in F44 and 1.11-2 in F43. — [packages.fedoraproject.org](https://packages.fedoraproject.org/pkgs/sway/sway/)
- **COPR swayfx/swayfx** has chroots for F44, F45 and Rawhide (x86_64 and aarch64). Its packages are manually uploaded SRPMs. The latest is swayfx **0.6-1**, built 2026-10-20, so it lags upstream 0.6.1. It also carries scenefx 0.5-1 plus compat packages (`scenefx-0.1`, `scenefx-0.2`, `scenefx-0.4.1`). — [COPR API](https://copr.fedorainfracloud.org/api_3/package/list?ownername=swayfx&projectname=swayfx), [repo](https://download.copr.fedorainfracloud.org/results/swayfx/swayfx/fedora-45-x86_64/)
- **Terra (terra45)** carries `swayfx 0.6.1-1.fc45`, `swayfx-config-upstream`, `swayfx-wallpapers` and `scenefx 0.5-1.fc45`. It also has `swaylock-effects` (which conflicts with `swaylock`) and `sway-audio-idle-inhibit`. — [Terra repo](https://repos.fyralabs.com/terra45/)
- RPM metadata from the COPR F45 build (Terra matches):
  - **`swayfx`**: `Provides: sway = 1.12`; `Conflicts: sway`; `Requires: sway-config, libscenefx-0.5.so, libwlroots-0.20.so`; `Suggests: swayfx-config-upstream`. No Obsoletes. Files: `/usr/bin/{sway,swaybar,swaymsg,swaynag}`, `/etc/sway/config.d`, `/usr/share/xdg-desktop-portal/sway-portals.conf`.
  - **`swayfx-config-upstream`**: `Provides: sway-config`; `Conflicts: sway-config`; ships `/etc/sway/config` and `/usr/share/wayland-sessions/sway.desktop`. — [COPR repodata](https://download.copr.fedorainfracloud.org/results/swayfx/swayfx/fedora-45-x86_64/repodata/)
- F44 has wlroots 0.20.2 plus a compat `wlroots0.19`, so the COPR F44 build of swayfx 0.6 (which links libwlroots-0.20) resolves on F44 too. — [mdapi f44 wlroots](https://mdapi.fedoraproject.org/f44/pkg/wlroots)

### Inferences
- `sway-config-fedora` needs `sway >= 1.8`, and swayfx's virtual `Provides: sway = 1.12` satisfies that. So `swayfx` plus `sway-config-fedora` is a valid pair, as long as both are installed in **one transaction**. Otherwise dnf may resolve `sway` to Fedora's real package.
- Consider `exclude=sway` in the repo config so updates can't pull Fedora's sway back in.

### Gaps
- I could not confirm whether the COPR or Terra spec adds patches beyond upstream. The COPR source is an uploaded SRPM.

---

## 2. Prior art

### Takeaway
Fedora Sway Atomic is alive and published as a bootc image. The Universal Blue sway images are **dead**. Wayblue (now `wayblueorg`) and secureblue still build sway images every day on top of Fedora's sway-atomic. Every Bazzite+Sway repo I found uses plain sway; **none ships SwayFX**.

### Cited Findings
- **Fedora Sway Atomic, Rawhide manifest** (`packages/sway-atomic.yaml`, generated from comps). Package list:
  - DM: `sddm`, `sddm-wayland-sway`
  - Sway core: `sway`, `sway-config-fedora`, `swaybg`, `swayidle`, `swaylock`, `waybar`, `dunst`, `foot`
  - Screenshots and clipboard: `grim`, `slurp`, `wl-clipboard`
  - Display: `kanshi`, `wlr-randr`, `wlsunset`
  - Portals and polkit: `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gtk`, `lxqt-policykit`, `polkit`
  - Tray and audio: `network-manager-applet`, `blueman`, `pavucontrol`, `pulseaudio-utils`, `playerctl`
  - Files: `Thunar`, `thunar-archive-plugin`, `gvfs`, `gvfs-smb`, `xarchiver`, `imv`
  - Other: `pam_oo7`, `tuned-ppd`, `tuned-switcher`, `wev`, `xorg-x11-server-Xwayland`, mesa drivers

  The OSTree ref keeps the legacy name `sericea`. — [forge.fedoraproject.org config](https://forge.fedoraproject.org/atomic-desktops/config/raw/branch/main/packages/sway-atomic.yaml), [common](https://forge.fedoraproject.org/atomic-desktops/config/raw/branch/main/sway-atomic-common.yaml)
- Official bootc image **quay.io/fedora/fedora-sway-atomic** has tags 43, 44, 45 and latest(=45), all refreshed 2026-11-22. — [quay API](https://quay.io/api/v1/repository/fedora/fedora-sway-atomic/tag/)
- **sway-config-fedora 0.4.3**:
  - Requires: `sway>=1.8`, `waybar`, `swaylock`, `swayidle`, `swaybg`, `grimshot`, `lxqt-policykit`, `brightnessctl`, `playerctl`, `pulseaudio-utils`, `desktop-backgrounds-compat`, `jxl-pixbuf-loader`.
  - Recommends: `foot`, `rofi-wayland`, `libnotify`, `sway-system​d`, `xdg-user-dirs`.
  - Its source package also builds `sddm-wayland-sway` and `initial-setup-gui-wayland-sway`.

  — [mdapi](https://mdapi.fedoraproject.org/f45/pkg/sway-config-fedora), [spec](https://src.fedoraproject.org/rpms/sway-config-fedora)
- How sway-config-fedora is wired:
  - **Layered include**: `/usr/share/sway/config.d/*.conf`, then `/etc/sway/config.d/*.conf`, then `~/.config/sway/config.d/*.conf`. A later file with the same name replaces an earlier one.
  - `sway.desktop` runs `Exec=start-sway`. `start-sway` sources the environment.d generator output, then `/etc/sway/environment` and `~/.config/sway/environment`, and honours `SWAY_EXTRA_ARGS`.
  - The polkit agent is started by `exec /usr/libexec/lxqt-policykit-agent`. XDG autostart runs through `sway-xdg-autostart.target` (from sway-systemd).

  — [gitlab.com/fedora/sigs/sway/sway-config-fedora](https://gitlab.com/fedora/sigs/sway/sway-config-fedora)
- **ublue-os sway images are deprecated and removed.** The README says "The deprecated sway, budgie, and cosmic images have now been removed, see #927" and "As of September 2025, this repo will only build base, kinoite, and silverblue images". `ghcr.io/ublue-os/sway-atomic-main:latest` was last built **2025-10-15** (F42); `sericea-main:gts` on 2025-06-07 (F41). BlueBuild base-images has no sway image either. — [ublue-os/main](https://github.com/ublue-os/main), [GHCR](https://ghcr.io/v2/ublue-os/sway-atomic-main/tags/list), [blue-build/base-images](https://github.com/blue-build/base-images)
- **Wayblue moved.** `github.com/wayblue/wayblue` returns 404; the project is now **github.com/wayblueorg/wayblue** (branch `live`, last push 2026-11-11, "considered beta").
  - `ghcr.io/wayblueorg/sway:latest` is 44.20261118.0, so it is **still on F44**.
  - The recipe uses `base-image: quay.io/fedora-ostree-desktops/sway-atomic`, `image-version: 44`, and adds SDDM theming, ublue udev/just/akmods, rofi-wayland, wofi and xfce-polkit.
  - SDDM is the default; `-gdm` variants are "not recommended"; `-nvidia` and `-nvidia-open` variants exist.

  — [README](https://github.com/wayblueorg/wayblue), [recipe-sway.yml](https://github.com/wayblueorg/wayblue/blob/live/recipes/recipe-sway.yml)
- **secureblue** `sericea-main-hardened` is built from `quay.io/fedora-ostree-desktops/sway-atomic:45`; the latest image is 45.20261121.0. — [recipe](https://github.com/secureblue/secureblue/blob/live/recipes/general/recipe-sericea-main.yml)
- **Bazzite + sway repos.** GitHub searches for "swayfx bazzite", "swayfx bluebuild" and "swayfx ublue" returned 0 results. Repos with plain sway:
  - [Smujb/bazzite-sway](https://github.com/Smujb/bazzite-sway): the most complete. `FROM bazzite-gnome:stable`, then `dnf5 remove *gnome* *gdm* ptyxis … --exclude=gnome-disk-utility,lutris,gnome-desktop3,gnome-keyring,gnome-keyring-pam`. Installs `sway-config-fedora sddm sddm-themes sddm-wayland-sway sway-systemd rofi-wayland mako xdg-desktop-portal-wlr` plus applets and thunar, then `systemctl enable sddm`.
  - [J4sp3r/bazzite-sway](https://github.com/J4sp3r/bazzite-sway): `FROM bazzite-dx-nvidia:stable@sha256…`, adds sway alongside the existing DE, and edits `image-info.json` and `VARIANT_ID`.
  - [guildeol/swazzite](https://github.com/guildeol/swazzite) and [nalch/swayzzite](https://github.com/nalch/swayzzite): minimal add-on on top of bazzite-gnome.
  - [LegitCamper/ublue-custom](https://github.com/LegitCamper/ublue-custom): BlueBuild sway, hyprland and niri recipes.

### Gaps
- I could not fetch the F45 branch of the Fedora manifest; the list above is from Rawhide/main.

---

## 3. Approach comparison

### Takeaway
Bazzite is now **F45** (`45.20261117.1`, kernel `7.3.4-ogc8.1.fc45`). Its desktop and gaming-mode scripts branch on `base-image-name` and only know `kinoite` and `silverblue`. Any approach that removes the DE has to patch those scripts.

### Cited Findings
- The Bazzite Containerfile defaults to `BASE_IMAGE_NAME=kinoite` and `FEDORA_VERSION=45`, built `FROM ghcr.io/ublue-os/${BASE_IMAGE_NAME}-main`. — [Containerfile](https://github.com/ublue-os/bazzite/blob/main/Containerfile); [GHCR labels](https://ghcr.io/v2/ublue-os/bazzite/manifests/stable)
- Bazzite turns Terra on with `priority=1` while building, but `finalize.sh` **disables** `terra`, `terra-extras` and the Bazzite COPRs in the shipped image. Derived builds need `--enablerepo=terra`. — [04-initialize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/04-initialize.sh), [finalize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/finalize.sh)
- Desktop-specific coupling:
  - `configure-kde.sh` installs `steamdeck-kde-presets-desktop`, `krunner-bazaar`, `krunner-yafti` and plasma pins.
  - `08-install-steam-lutris.sh` installs `plasma-foreground-booster-dmemcg` on KDE, and otherwise runs `dnf5 swap --repo terra-extras uresourced uresourced-dmemcg`.
  - `90-bazzite-de.just` is DE-specific; on KDE it is the Breeze GTK restore.

  — [configure-kde.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/desktop_env/configure-kde.sh), [08-install-steam-lutris.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/08-install-steam-lutris.sh)
- Scripts that hard-code DEs:
  - `os-session-select` picks `plasma.desktop` for kinoite and `gnome.desktop` for anything else.
  - `bazzite-autologin` maps kinoite to `plasma.desktop` and silverblue to `gnome.desktop`; anything else gets "Unknown base image …, leaving autologin alone".
  - `04-finalize.sh` appends `[session] desktop = "plasma.desktop"|"gnome.desktop"` to `/usr/share/steamos-manager/platform.toml`.

  — [os-session-select](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/os-session-select), [bazzite-autologin](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/bazzite-autologin), [deck 04-finalize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/04-finalize.sh)
- Steam autostarts for every session through `/etc/skel/.config/autostart/steam.desktop` (`bazzite-steam -silent`). Sway runs XDG autostart too, through `sway-xdg-autostart.target`. — [12-finalize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/12-finalize.sh)

### Pros, cons and breakage per approach
- **(a) Keep Bazzite KDE and add SwayFX as an extra session.**
  - Pros: every Bazzite script, ujust recipe and update path keeps working; Plasma stays as a fallback; the smallest diff.
  - Cons: a large image with duplicate stacks.
  - Breakage risks:
    - Portal backends: sway-portals.conf (`default=gtk`) needs xdg-desktop-portal-gtk present. Whether Bazzite KDE ships it is UNVERIFIED, so install it explicitly.
    - Secret service: KWallet under KDE versus `Secret=gnome-keyring` in sway-portals.conf, and F45 moved to oo7 (see section 5).
    - Qt theming leaks in from Plasma.
    - The greeter is Plasma Login Manager (see section 6).
- **(b) Remove Plasma and put SwayFX in its place.**
  - Pros: one coherent stack, smaller image.
  - Cons: removing Plasma has a wide dependency blast radius. You must:
    - swap `plasma-foreground-booster-dmemcg` for `uresourced-dmemcg`;
    - drop the KDE presets;
    - patch `os-session-select`, `bazzite-autologin` and `platform.toml` to use `sway.desktop`;
    - decide what `base-image-name` in `image-info.json` should say. Changing it breaks the scripts above; keeping `kinoite` makes them pick Plasma.

  The proven removal precedent is GNOME, not Plasma (Smujb's repo, starting from bazzite-gnome).
- **(c) Start from `quay.io/fedora/fedora-sway-atomic:45` (or wayblue/secureblue) and re-add the gaming stack.**
  - Pros: Fedora's tested sway defaults, SDDM with the sway greeter, clean portals.
  - Cons: you re-implement roughly 12 Bazzite build scripts: the ogc kernel and akmods, `terra-gamescope`, `terra-mangohud`, `vkBasalt`, `steam`, `lutris`, umu, scx-scheds, ntsync, game-devices-udev, inputplumber, steamos-manager, gamescope-session. You lose `ujust`, `bazzite-updater` and Bazzite support. Wayblue lags at F44, and `ublue-os/sway-atomic-main` is dead.

---

## 4. Gaming under sway/SwayFX

### Takeaway
Upstream sway 1.12 brought HDR10 (Vulkan renderer only), NVIDIA tolerance, tearing control and explicit sync. **SwayFX always uses scenefx's GLES renderer, so HDR is effectively unavailable.** Steam Gaming Mode exists only in the `bazzite-deck*` images.

### Cited Findings
- **Sway 1.12** (2026-05-25):
  - "Add support for HDR10 when running with the Vulkan renderer"
  - color-management-v1 and color-representation-v1
  - "Sway no longer refuses to start on unsupported GPUs (e.g. NVIDIA proprietary drivers)"

  — [sway 1.12](https://github.com/swaywm/sway/releases/tag/1.12)
- **NVIDIA handling.** sway 1.12 and swayfx 0.6.1 both still show a swaynag warning unless launched with `--unsupported-gpu` or `SWAY_UNSUPPORTED_GPU=true`. — [sway main.c](https://github.com/swaywm/sway/blob/1.12/sway/main.c), [swayfx main.c](https://github.com/wlrfx/swayfx/blob/0.6.1/sway/main.c). In July 2026 Garuda was waiting for the swayfx 1.12 rebase to get this env var. — [Garuda forum](https://forum.garudalinux.org/t/garuda-sway-nvidia-call-for-testers/48296)
- Explicit sync (`linux-drm-syncobj-v1`) arrived in sway **1.11** (2025-06-08). Tearing-control-v1 arrived in **1.10** (2024-10-27). — [1.11](https://github.com/swaywm/sway/releases/tag/1.11), [1.10](https://github.com/swaywm/sway/releases/tag/1.10)
- SwayFX 0.6.1 keeps the tearing page-flip path and includes the syncobj header in `server.c`. — [server.c](https://github.com/wlrfx/swayfx/blob/0.6.1/sway/server.c), [output.c](https://github.com/wlrfx/swayfx/blob/0.6.1/sway/desktop/output.c)
- **SwayFX's renderer.** `server.c` always calls `fx_renderer_create()`, and scenefx is EGL/GLESv2. — [scenefx README](https://github.com/wlrfx/scenefx). An open issue, #558 "Unable to use vulkan renderer" (2026-08-06), confirms it. — [issues](https://github.com/wlrfx/swayfx/issues)
- The sway-output(5) syntax: — [sway-output.5.scd](https://github.com/swaywm/sway/blob/master/sway/sway-output.5.scd)
  - `adaptive_sync on|off|toggle` ("can cause flickering on some hardware")
  - `allow_tearing yes|no`: fullscreen only, the app must also allow it, and `max_render_time off` is recommended
  - `hdr on|off|toggle`: implies 10-bit; the renderer must support it
  - `render_bit_depth 6|8|10`
- Open SwayFX issues that matter for gaming and stability (from the issues list):
  - #628: a Minecraft fork crashes swayfx (2026-11-16)
  - #623 and #557: animation crashes
  - #562: animations capped at 60 fps
  - #600: NVIDIA corner notch on 0.6
  - #585: screensharing fails with blur when a window changes workspace
  - #587: fullscreen windows are not dimmed

  — [issues](https://github.com/wlrfx/swayfx/issues)
- **Gaming Mode.** The Bazzite FAQ says Steam Gaming Mode is not in the desktop images; `bazzite-deck` and `bazzite-deck-nvidia` boot into it. — [Bazzite FAQ](https://docs.bazzite.gg/General/FAQ/)
  - The deck build installs `sddm`, removes `plasma-login-manager`, and adds `gamescope-session-ogui-steam`, `steamos-manager-powerstation` and `inputplumber`. — [deck 01](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/01-configure-desktop.sh), [deck 02](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/02-install-packages.sh)
  - `holo.conf` sets `Relogin=true` and `Session=gamescope-session-ogui-steam.desktop`. — [holo.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf)
- Terra ships the session files:
  - `gamescope-session` (provides `gamescope-session-plus@.service`)
  - `gamescope-session-steam` (`/usr/share/wayland-sessions/gamescope-session-steam.desktop`, `steamos-session-select`)
  - `gamescope-session-ogui-steam`
  - `steamos-manager 26.4.1` (`steamosctl`)

  — [Terra repo](https://repos.fyralabs.com/terra45/)
- Bazzite already ships `terra-gamescope`, `terra-mangohud` (x86_64 and i686), `vkBasalt`, `game-devices-udev`, `steam` and `lutris` in every image. — [08-install-steam-lutris.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/08-install-steam-lutris.sh)

### Inferences
- For HDR games under SwayFX, launch them through `gamescope` in its embedded or DRM session (the Gaming Mode session), not nested. Upstream sway with `WLR_RENDERER=vulkan` is the alternative.
- Nested gamescope works on wlroots compositors. I found no SwayFX-specific gamescope bug.

### Gaps
- Whether scenefx effects defeat direct scanout for fullscreen games, which would add latency: UNVERIFIED.
- NVIDIA explicit sync was not runtime-tested on SwayFX: UNVERIFIED.

---

## 5. Desktop pieces and where they go in an image

### Cited Findings
- F45 package names and versions: — [mdapi f45](https://mdapi.fedoraproject.org/f45/pkg/)
  - `rofi 2.1.0` **obsoletes `rofi-wayland`**
  - `fuzzel 1.15.0`, `wofi`
  - `mako 1.11.0`, `SwayNotificationCenter 0.12.6`, `dunst`
  - `waybar 0.16.0`
  - `xdg-desktop-portal-wlr 0.9.0`, `xdg-desktop-portal-gtk 1.15.3`
  - `lxqt-policykit 2.5.0`, `mate-polkit` (`polkit-gnome` is not in F45)
  - `swaylock 1.8.6`, `swayidle 1.9.1`
  - `grim`, `slurp`, `grimshot 1.12`
  - `kanshi`, `wdisplays`, `wlogout`
  - `network-manager-applet`, `blueman`, `pavucontrol`
  - `Thunar`, `foot 1.28`, `cliphist`, `wl-clipboard`
  - `sway-systemd 0.4.1`
  - **`pam_oo7` obsoletes `gnome-keyring-pam`**
- Not in F45: `swayosd`, `nwg-look`, `nwg-displays`. Terra has `nwg-look` and `nwg-displays`. — [Terra](https://repos.fyralabs.com/terra45/)
- Fedora's sway-portals.conf: `default=gtk`; `ScreenCast=wlr`; `Screenshot=wlr`; `Secret=gnome-keyring`; `Inhibit=none`. swayfx ships the same file at `/usr/share/xdg-desktop-portal/sway-portals.conf`. — [Fedora dist-git](https://src.fedoraproject.org/rpms/sway/blob/rawhide/f/sway-portals.conf)
- SwayFX directives:
  - `blur`, `blur_passes`, `blur_radius`, `blur_noise`, `blur_brightness`, `blur_contrast`, `blur_saturation`, `blur_xray`
  - `corner_radius`
  - `shadows`, `shadows_on_csd`, `shadow_blur_radius`, `shadow_color #RRGGBBAA`, `shadow_offset`, `shadow_inactive_color`
  - `default_dim_inactive`, `for_window [..] dim_inactive`, `dim_inactive_colors.unfocused|urgent`
  - `layer_effects <ns> {…}`, with `blur`, `blur_xray`, `blur_ignore_transparent`, `shadows`, `corner_radius`, `reset`
  - `titlebar_separator`, `scratchpad_minimize` ("recommend keeping this off")
  - `animation_duration_ms 0-5000`

  — [README](https://github.com/wlrfx/swayfx)

### Where to put things
- Immutable vendor snippets go in `/usr/share/sway/config.d/NN-*.conf`. Admin overrides go in `/etc/sway/config.d/`, and a file with the same name replaces the vendor one.
- Ship environment variables in `/usr/lib/environment.d/*.conf` (read by start-sway's generator) or `/etc/sway/environment`.
- The session file is `/usr/share/wayland-sessions/sway.desktop`, from sway-config-fedora.
- Keep `/etc/skel` for user dotfiles only.

### Snippets
```conf
# /usr/share/sway/config.d/80-swayfx.conf
corner_radius 8
blur enable
blur_passes 2
blur_radius 5
blur_xray disable
shadows enable
shadow_blur_radius 20
shadow_color #0000007F
default_dim_inactive 0.1
dim_inactive_colors.unfocused #000000FF
animation_duration_ms 150
layer_effects "waybar" {
    blur enable;
    blur_ignore_transparent enable;
    shadows enable;
    corner_radius 10;
}
```
```conf
# /usr/share/sway/config.d/70-gaming.conf
output * adaptive_sync on
output * allow_tearing yes
output * max_render_time off
for_window [class="^steam_app_"] inhibit_idle fullscreen
```
```conf
# /usr/lib/environment.d/90-sway-nvidia.conf   (nvidia images only)
SWAY_UNSUPPORTED_GPU=true
```

### Gaps
- Secret portal on F45 now that oo7 replaces gnome-keyring-pam: `Secret=gnome-keyring` may need `oo7-portal`. UNVERIFIED.
- Per-window blur or shadow disable criteria: not documented in the README. UNVERIFIED.

---

## 6. Display manager

### Takeaway
**The premise that Bazzite uses SDDM is out of date.** Since F44, Bazzite KDE desktop uses **Plasma Login Manager (PLM)**. SDDM survives only in `bazzite-deck*`, because steamos-manager session switching relies on SDDM `sddm.conf.d` drop-ins. Sway runs fine under SDDM; that is Fedora Sway Atomic's default.

### Cited Findings
- Fedora 44 switched all KDE variants, Kinoite included, from SDDM to PLM. — [Fedora Change](https://fedoraproject.org/wiki/Changes/PlasmaLoginManager)
- Bazzite ships `/usr/lib/plasmalogin/defaults.conf` for kinoite. — [file](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/kinoite/usr/lib/plasmalogin/defaults.conf)
- F45 has `plasma-login-manager 6.8.1`, `sddm 0.21.0` and `sddm-wayland-sway 0.4.3`. — [mdapi](https://mdapi.fedoraproject.org/f45/pkg/sddm-wayland-sway)
- `sddm-wayland-sway` declares `Provides`/`Conflicts: sddm-greeter-displayserver` and sets `CompositorCommand=/usr/libexec/sddm-compositor-sway` with theme `03-sway-fedora`. — [spec](https://src.fedoraproject.org/rpms/sway-config-fedora), [wayland-sway.conf](https://gitlab.com/fedora/sigs/sway/sway-config-fedora)
- `bazzite-autologin` writes `/etc/sddm.conf.d/zz-bazzite-autologin.conf` and `zz-holo-autologin.conf`. Stale `zzt-steamos-temp-login.conf` drop-ins have broken switching between Gaming Mode and desktop (issue #5047, Jun–Nov 2026). — [#5047](https://github.com/ublue-os/bazzite/issues/5047)
- CachyOS users report that PLM ignores the steamos-manager switch request (forum, anecdotal). — [CachyOS](https://discuss.cachyos.org/t/cannot-switch-back-to-game-mode-after-recent-update/37133?page=2)
- Packaging of greetd greeters: `greetd 0.10.3`, `tuigreet 0.9.1` and `gtkgreet` are in F45. **regreet is in neither Fedora nor Terra.** — [mdapi](https://mdapi.fedoraproject.org/f45/pkg/greetd)

### Trade-offs
- **SDDM** is required if you want `steamosctl` / `os-session-select` / "Return to Gaming Mode" to work.
- **greetd** works for a pure desktop, but you would have to rewrite the autologin and session-switch logic.
- **PLM** (approach a on KDE): it lists `/usr/share/wayland-sessions/*`, but this is UNVERIFIED for third-party sessions.
- Don't install `sddm-wayland-sway` on bazzite-deck KDE. It conflicts with the existing greeter display server (assumed to be sddm-wayland-plasma, which provides the same virtual: UNVERIFIED).

---

## Recommendation

- **Desktop or laptop, no Gaming Mode:** use **(a)**. `FROM ghcr.io/ublue-os/bazzite:stable` (or `-nvidia`), then add SwayFX as a second session. This is the lowest-risk option.
- **Gaming Mode wanted:** also **(a)**, but on **`bazzite-deck` / `bazzite-deck-nvidia`**, which keeps SDDM and the gamescope-session machinery. Then patch `platform.toml` `[session] desktop = "sway.desktop"`, plus `os-session-select` and `bazzite-autologin`, if sway should be the desktop mode.
- **(b):** only from `bazzite-gnome`, following Smujb's precedent.
- **(c):** only if you want Fedora Sway Atomic first and accept rebuilding Bazzite's gaming stack.

```dockerfile
FROM ghcr.io/ublue-os/bazzite:stable
RUN dnf5 -y install --enablerepo=terra swayfx sway-config-fedora \
      sway-systemd xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
      mako fuzzel grim slurp wl-clipboard cliphist kanshi wlogout \
      network-manager-applet blueman pavucontrol Thunar thunar-archive-plugin gvfs foot \
 && dnf5 config-manager setopt fedora.exclude=sway updates.exclude=sway \
 && bootc container lint
```
`sway-config-fedora` pulls in waybar, swaylock, swayidle, swaybg, grimshot, lxqt-policykit, brightnessctl and playerctl. `rofi` comes in via its Recommends. Steam, gamescope, MangoHud and vkBasalt are already in Bazzite. The fedora/updates exclude line follows the section 1 advice and is optional.
