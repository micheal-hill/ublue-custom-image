# Base image inspection (2026-11-22)

Read directly from the pulled base images with `podman run --rm --entrypoint bash <image> -c …`.
This settles the items the research marked UNVERIFIED.

| Image | Version | Size (unpacked) |
|---|---|---|
| `ghcr.io/ublue-os/bazzite-nvidia:stable` | 45.20261117.1 | 12.3 GB |
| `ghcr.io/ublue-os/bazzite-deck:stable` | 45.20261117.x | (pulled, similar) |

## Shared by both bases

- **`/usr/share/ublue-os/image-info.json`** has the fields `image-name`, `image-vendor`, `image-ref`,
  `image-tag`, `image-branch`, `base-image-name` (`kinoite`), `fedora-version` (`45`), `version` and
  `version-pretty`.
- **Tools present:** `jq` (`/usr/sbin/jq`), `dnf5`, `bootc`. `steamosctl` is present **only on deck**.
- **Repos:**
  - Enabled: `fedora`, `updates`, and **`updates-archive`**, which keeps older builds such as previous Plasma point releases.
  - Disabled: `terra`, `terra-extras` and `terra-mesa`, every `ublue-os` COPR, and the negativo17
    `fedora-multimedia` and `fedora-nvidia*` repos.
  - **The Terra repo id is `terra`.**
- **Versionlock:** 256 locks.
  - The kernel is locked (nvidia base: `6.18.60-ogc1.2.fc45`).
  - `plasma-*` is locked by name to every EVR that was available at build time. That includes
    `plasma-bigscreen`, `plasma-bigscreen-wayland`, `plasma-keyboard` and `plasma-nano`, at
    6.8.1, 6.8.2 and 6.8.3.
  - So Bigscreen can never be installed ahead of the base's Plasma version, and `updates-archive`
    keeps the locked builds installable after Fedora moves on.
- **Plasma:** `plasma-workspace`, `kwin` and `libplasma` are 6.8.3-1.fc45. Qt is `qt6-qtbase` 6.11.2.
  - `plasma-workspace-wayland` is not a separate package. `plasma-workspace` itself
    `Provides: plasma-workspace-wayland = 6.8.3-1.fc45`, which satisfies `plasma-bigscreen-wayland`'s requirement.
- **Signing:**
  - `/etc/containers/policy.json` exists. There is no `/usr/etc` copy.
  - The docker scopes are `""` (default), `ghcr.io/ublue-os`, `quay.io/toolbx-images`,
    `registry.access.redhat.com` and `registry.redhat.io`.
  - Existing files: `registries.d/{ublue-os,quay.io-toolbx-images}.yaml` and
    `/etc/pki/containers/{ublue-os,ublue-os-backup,quay.io-toolbx-images}.pub`.
- **Flatpak browser:** `org.mozilla.firefox`, listed in `/usr/share/ublue-os/bazzite/flatpak/install`.
- **Portals:** `xdg-desktop-portal-gtk` 1.15.3 and `-kde` 6.8.3 are installed. `-wlr` is not
  installed (0.8.5 is available in `updates`).
- **Audio:** **`terra-wireplumber` 0.5.18** (not Fedora's `wireplumber`), with vendor drop-ins in
  `/usr/share/wireplumber/wireplumber.conf.d/`.

## `bazzite-nvidia` (desktop image, SwayFX base)

- **Login manager:** Plasma Login Manager `plasma-login-manager-6.8.3`. SDDM is not installed.
  - `/etc/plasmalogin.conf` documents only SDDM-style keys: `[Autologin] Relogin/Session/User`,
    `[Users] RememberLastSession=true`, `RememberLastUser`, `ReuseSession`.
  - **There is no "default session" key.** The greeter remembers the last session. So SwayFX is
    picked once at login; or autologin, which needs a username.
  - Drop-in directory `/usr/lib/plasmalogin/plasmalogin.conf.d/` exists and is empty.
    `/usr/lib/plasmalogin/defaults.conf` only sets the greeter wallpaper.
  - Warning: running `plasmalogin --example-config` in a container hangs, because it starts the
    daemon. Don't do it.
- **Sessions:** only `plasma.desktop` in `/usr/share/wayland-sessions/`.
- **Steam autostart:** `/etc/skel/.config/autostart/` contains `steam.desktop` (starts Steam silently
  in every session) and `bazzite-portal.desktop`.
- **SwayFX stack availability** (`dnf5 repoquery --enablerepo=terra`):

  | Package | Version | Repo |
  |---|---|---|
  | `swayfx` | 0.6.1-1.fc45 | **terra only** |
  | `swayfx-config-upstream` | 0.6.1-1.fc45 | terra |
  | `scenefx` | 0.5-1.fc45 | fedora (also terra) |
  | `sway` (stock) | 1.12-2.fc45 | fedora |
  | `sway-config-fedora` | 0.4.3-4.fc45 | fedora |
  | `sway-systemd` | 0.4.1-5.fc45 | fedora |
  | `xdg-desktop-portal-wlr` | 0.8.5-1.fc45 | updates |
  | `fuzzel` | 1.15.0 | updates |
  | `mako` | 1.11.0 | fedora |
  | `cliphist` | 0.7.0 | fedora |
  | `wlogout` | 1.2.2 | fedora |
  | `kanshi` | 1.9.0 | fedora |
  | `Thunar` | 4.20.10 | fedora |
  | `foot` | 1.28.0 | fedora |

  `sway-config-fedora` requires: `sway >= 1.8`, `waybar`, `swaylock`, `swayidle`, `swaybg`,
  `grimshot`, `lxqt-policykit`, `brightnessctl`, `playerctl`, `pulseaudio-utils`,
  `desktop-backgrounds-compat`, `jxl-pixbuf-loader`, `xorg-x11-server-Xwayland`, `mesa-dri-drivers`
  and `polkit`.

## `bazzite-deck` (HTPC image, Bigscreen base)

- **Login manager:** SDDM 0.21.0. PLM is not installed.
  - `/usr/lib/sddm/sddm.conf.d/holo.conf` contains `[Autologin] Relogin=true`,
    `Session=gamescope-session-ogui-steam.desktop`.
  - `plasma-wayland.conf` runs the greeter on `kwin_wayland … --inputmethod plasma-keyboard`.
  - `/etc/sddm.conf.d/virtualkbd.conf` contains `InputMethod=qtvirtualkeyboard`.
- **Sessions:** `gamescope-session-ogui-steam.desktop`, `gamescope-session-steam.desktop` and `plasma.desktop`.
- **`/usr/libexec/bazzite-autologin`**, run by `bazzite-autologin.service` before
  display-manager on every boot:
  - With no `/etc/bazzite/desktop_autologin`, the session is `gamescope-session-ogui-steam.desktop`.
  - With the flag present on a kinoite base, it is **`SESSION="plasma.desktop"`**.
  - It writes `/etc/sddm.conf.d/zz-bazzite-autologin.conf` (`User=` uid 1000), and
    `zz-holo-autologin.conf` (`Session=`) **only if that file doesn't exist yet**.
  - `/etc/bazzite/` does not exist in the image.
- **`/usr/libexec/os-session-select`** (deprecated, kept for Steam compatibility):
  - `desktop_session="plasma.desktop"` when `base-image-name == kinoite`.
  - It is used for `set-default-desktop-session` and `switch-to-desktop-mode`.
- **`/usr/share/steamos-manager/platform.toml`:** `[session] desktop = "plasma.desktop"`.
- **ujust `95-bazzite-deck-session.just`:** `steamosctl set-default-login-mode game|desktop`.
- **Steam launcher:** `/usr/share/applications/steam.desktop` main entry
  `Exec=/usr/bin/bazzite-steam %U`, plus actions (Big Picture, Library, …).
  `opengamepadui.desktop` is present. There is no Steam autostart in `/etc/skel` on deck.
- **Bigscreen availability:**

  | Package | Versions available |
  |---|---|
  | `plasma-bigscreen`, `plasma-bigscreen-wayland` | 6.8.1 (fedora), 6.8.2 (updates-archive), **6.8.3 (updates)** |
  | `plasma-keyboard` | 6.8.3, **already installed** |
  | `plasma-nano` | not installed (pulled in as a dependency) |
  | `kde-connect` / `kdeconnectd` | 26.08.3, installed |

## Verification of the locally built images (2026-11-22)

Both images were built with host podman: `just build <image>`, with `podman` forwarded from the
distrobox through a `distrobox-host-exec` symlink.

| Check | `bazzite-swayfx-nvidia` | `bazzite-bigscreen` |
|---|---|---|
| `bootc container lint` | 14 passed, 0 warnings | 14 passed, 0 warnings |
| Size (unpacked) | 12.5 GB | 12.2 GB |
| Key packages | `swayfx-0.6.1-1.fc45` (only package taken from Terra), `rofi-2.1.0`, `xdg-desktop-portal-wlr-0.8.5` | `plasma-bigscreen{,-wayland}-6.8.3-1` = `plasma-workspace-6.8.3-1`, `plasma-nano-6.8.3`, `plasma-keyboard-6.8.3` |
| Sessions | `plasma.desktop`, `sway.desktop` (Name=SwayFX) | `plasma-bigscreen-wayland.desktop` plus the gamescope sessions and `plasma.desktop` |
| Config check | `sway --validate` of the full config (Fedora's plus ours) exits 0. A bogus directive fails as expected. | `platform.toml` still parses as TOML. Patched scripts pass `bash -n` and keep mode 755. |
| Runtime dry-run | n/a | `bazzite-autologin`, run with a uid-1000 user, writes `zz-holo-autologin.conf` with `Session=plasma-bigscreen-wayland.desktop` |
| Audio rule | n/a | `pw-config --prefix /usr/share/wireplumber … merge monitor.alsa.rules` parses `60-prefer-hdmi.conf` |

Lessons from the build:

- **Fedora's sway config uses `rofi` as `$menu`.** Bazzite skips weak dependencies, so `rofi` must
  be listed explicitly.
- **`/run/dnf`, `/var/lib/dnf` and `/var/lib/blueman` trigger bootc lint warnings.** `build.sh`
  removes the dnf leftovers. `/var/lib/blueman` gets a tmpfiles.d entry instead.
- **Podman's layer cache ignores bind-mounted `ctx` content.** A rebuild reused a stale `RUN
  build.sh` layer after the scripts changed. `just build` now passes `--no-cache`; the dnf cache
  mount keeps rebuilds fast (13–21 s).
- **Validating sway inside a container takes several workarounds:**
  - Copy the binary first, because `/usr/bin/sway` carries `cap_sys_nice`, which a rootless
    container can't execute.
  - Use the headless backend.
  - Pass the Intel render node via `WLR_RENDER_DRM_DEVICE`. The image's NVIDIA 580.196 userspace
    doesn't match the host's 580.178 kernel driver.
- **A bootc-image-builder qcow2 has no user account, and Bazzite has no first-run wizard.**
  `just build-qcow2` therefore prompts for a VM user.
