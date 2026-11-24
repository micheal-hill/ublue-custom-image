<!-- Research notes gathered 2026-11-22 by a research subagent (web + GitHub/registry APIs). -->

# Shipping KDE Plasma Bigscreen in a Bazzite-derived bootc image (state as of 2026-11-22)

Method: KDE GitLab API, Fedora dist-git/Bodhi/mdapi, the GitHub API and raw files, and the KDE, plasma-bigscreen.org and Bazzite docs pages. `gh` and `dnf` were not installed, so I used curl against the public APIs instead.

**Data caveat:** mdapi's `f44-updates` data looked stale. It still showed plasma-bigscreen at the Feb 2026 6.5.80 snapshot and libplasma at 6.6.4, while Bodhi shows 6.8.3 stable on F44. Bodhi is the source used for versions below.

---

## Q1. Status of Plasma Bigscreen in late 2026

### Takeaway
Bigscreen was revived on Plasma 6 and has been a regular part of the Plasma release set since 6.7 (beta 14 May 2026, final 16 June 2026). The current release is **v6.8.3 (2026-11-10)**. It runs on Wayland only, and the old `plasma-remotecontrollers` daemon is archived; its job is now done by the built-in `plasma-bigscreen-inputhandler`.

### Cited Findings
- **Tags:** v6.6.90 (2026-05-14), v6.7.0 (2026-06-11), 6.7.1–6.7.5, v6.8.0 (2026-10-08), v6.8.1, v6.8.2, **v6.8.3 (2026-11-10)**, and a 6.7 LTS-style v6.7.6 (2026-11-03) — [KDE GitLab tags API](https://invent.kde.org/api/v4/projects/plasma%2Fplasma-bigscreen/repository/tags)
- The Plasma 6.7 beta lists `plasma-bigscreen` under "new modules" — [KDE 6.6.90 announcement](https://kde.org/announcements/plasma/6/6.6.90/); [GamingOnLinux](https://www.gamingonlinux.com/2026/05/kde-plasma-6-7-beta-arrives-with-plasma-bigscreen-new-union-theme-system/)
- Plasma 6.7 was released Tuesday 16 June 2026. The announcement text itself says nothing about Bigscreen — [kde.org 6.7.0](https://kde.org/announcements/plasma/6/6.7.0/)
- Plasma 6.8 was released 14 Oct 2026. Starting X11 sessions is "being retired", with XWayland kept. It adds NVIDIA HDR improvements when using an ICC profile, and HLG transfer-function support — [kde.org 6.8.0](https://kde.org/announcements/plasma/6/6.8.0/)
- The project blog's "Hello" post (5 Nov 2026) says the shell joined the Plasma release cycle "starting in Plasma 6.7" and is still under active development. "November 2026 App Releases" (11 Nov 2026) introduces "Bigscreen UI", a shared Qt Quick/Kirigami component library for TV apps — [plasma-bigscreen.org/blog](https://plasma-bigscreen.org/blog/)
- The README calls it "a … Wayland desktop environment designed for devices like HTPCs and SBCs". Components:
  - homescreen containment
  - envmanager
  - inputhandler (CEC plus game controllers)
  - KCMs and a standalone settings app
  - uvcviewer (capture-card viewer)
  - webapp-viewer

  [README v6.8.3](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/README.md)
- **Build requirements:**
  - Qt ≥ 6.11.0, KF6 ≥ 6.14.0, Plasma deps ≥ 6.8.0, QCoro ≥ 0.7
  - **SDL3 is required** (controllers)
  - **libcec ≥ 6 is optional** (pkg-config; TV remotes)
  - `org.kde.kdeconnect` QML module is required
  - Qt WebEngine and Multimedia are required

  [CMakeLists.txt v6.8.3](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/CMakeLists.txt)
- **Maintainers:** copyright headers name Aditya Mehra and Marco Martin (original, 2019), Bart Ribbers, Aleix Pol, Devin Lin and Seshan Ravikumar (Sineware, 2025). Human commit authors since May 2026: Devin Lin (10), "User8395" (8), Wolf Luyten (5), plus single commits from others — [commits API](https://invent.kde.org/api/v4/projects/plasma%2Fplasma-bigscreen/repository/commits); [bin/CMakeLists.txt](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/bin/CMakeLists.txt)
- **Controller mapping** (Xbox naming): A=Enter, B=Back/Esc, D-pad/left stick=arrows, right stick=mouse, Guide=Meta, Start=Games key. "Input suspension" stops Bigscreen handling the controller while an app reads it, to avoid double events.
- **CEC:** most PCs need an adapter (Pulse-Eight given as the example). TVs often keep the Back/Home keys for themselves, so a separate air remote is recommended. KDE Connect works as a phone remote — [docs/inputs](https://plasma-bigscreen.org/docs/inputs/)
- `plasma-bigscreen/plasma-remotecontrollers` is **archived** (last activity 2026-07-27) — [KDE GitLab](https://invent.kde.org/plasma-bigscreen/plasma-remotecontrollers)
- **Companion apps:** `aura-browser` and `plank-player` are both tagged **v26.11.0 (2026-11-04)** and live in the `plasma-bigscreen` group, not `plasma/`. A new `encore-music` player is also active (2026-10-30) — [aura-browser](https://invent.kde.org/plasma-bigscreen/aura-browser), [plank-player](https://invent.kde.org/plasma-bigscreen/plank-player), [group](https://invent.kde.org/plasma-bigscreen)
- **Voice assistant:** Mycroft integration was "obsoleted by late 2024" — [Wikipedia](https://en.wikipedia.org/wiki/Plasma_Bigscreen).
  - Mycroft-era repos are archived: `mycroft-ptt-client`, `mycroft-skill-installer`, `mycroft-bigscreen-setup`, and two `bigscreen-*-skill` repos.
  - The `*-voice-application` repos are not archived and show activity in Nov 2026 — [group listing](https://invent.kde.org/plasma-bigscreen)
- The Fedora spec obsoletes the old `-x11` subpackage. Only a Wayland session is built — [Fedora spec](https://src.fedoraproject.org/rpms/plasma-bigscreen/blob/rawhide/f/plasma-bigscreen.spec)

### Inferences
- No voice-assistant code is in the shell build: there are no Mycroft or OVOS dependencies in CMakeLists. Treat voice as absent.
- The Nov 2026 activity in the voice-app repos is probably translation-bot commits only. UNVERIFIED.
- Envmanager sets `BrowserApplication=aura-browser`. If Aura is not installed, the default browser for links will break.

### Gaps
- I did not find release notes listing Bigscreen-specific changes per 6.7 or 6.8 release.
- The KDE announcements mention Bigscreen only in their footer links.

---

## Q2. Fedora packaging

### Takeaway
**`plasma-bigscreen` and `plasma-bigscreen-wayland` are in official Fedora repos** (F43, F44, F45, F46/rawhide, ELN), packaged by Steve Cossette. No COPR is needed. `plasma-remotecontrollers`, `aura-browser` and `plank-player` are **not** in Fedora.

### Cited Findings
- **Bodhi stable updates:**
  - `plasma-bigscreen-6.8.3-1.fc44` (FEDORA-2026-5cc225ea97, submitted 2026-11-13)
  - `6.8.3-1.fc45` (FEDORA-2026-78c0581f85)
  - `6.8.3-1.fc46`
  - `6.7.6-1.fc43` (FEDORA-2026-651aca0533)

  [Bodhi](https://bodhi.fedoraproject.org/updates/?packages=plasma-bigscreen)
- **Plasma core alignment:**
  - F44: plasma-workspace, kwin and libplasma 6.8.3 went stable on 2026-11-16.
  - F45: the same on 2026-11-15.
  - F43 stays on **6.7.6**, still shipping `plasma-workspace-x11` and `kwin-x11`.

  [Bodhi plasma-workspace](https://bodhi.fedoraproject.org/updates/?packages=plasma-workspace)
- **Spec facts** — [Fedora spec](https://src.fedoraproject.org/rpms/plasma-bigscreen/blob/rawhide/f/plasma-bigscreen.spec):
  - Source is `download.kde.org/stable/plasma/%{version}/`; the comment "Not currently in the plasma releases" is stale.
  - Main package `Requires: plasma-bigscreen-wayland`, `qt6qml(org.kde.plasma.private.nanoshell)` (from plasma-nano) and `qt6qml(org.kde.kdeconnect)`.
  - `-wayland` (noarch) `Requires: plasma-workspace-wayland >= %{version}`.
  - `ExclusiveArch` is limited to QtWebEngine arches.
- **Files installed:**
  - `/usr/bin/plasma-bigscreen-{common-env,envmanager,settings,swap-session,uvcviewer,wayland,webapp,inputhandler}`
  - `kcm_mediacenter_*`
  - look-and-feel and shell `org.kde.plasma.bigscreen`
  - `/usr/lib/udev/rules.d/40-uinput.rules`
  - `/usr/share/applications/plasma-bigscreen-swap-session.desktop`
  - **session file: `/usr/share/wayland-sessions/plasma-bigscreen-wayland.desktop`** (in the `-wayland` subpackage)

  [Fedora spec](https://src.fedoraproject.org/rpms/plasma-bigscreen/blob/rawhide/f/plasma-bigscreen.spec)
- **Session desktop entry:** `Exec=/usr/libexec/plasma-dbus-run-session-if-needed /usr/bin/plasma-bigscreen-wayland`, `DesktopNames=KDE`. The launcher sources `plasma-bigscreen-common-env`, then runs `startplasma-wayland --xwayland --libinput --exit-with-session=…/startplasma-waylandsession`. A `-dev` session is configured but not installed — [bin/](https://invent.kde.org/plasma/plasma-bigscreen/-/tree/v6.8.3/bin)
- **`common-env` sets:**
  - `PLASMA_PLATFORM=mediacenter`
  - `QT_FILE_SELECTORS=mediacenter`
  - `PLASMA_DEFAULT_SHELL=org.kde.plasma.bigscreen`
  - `KWIN_IM_SHOW_ALWAYS=1`
  - prepends `$HOME/.config/plasma-bigscreen` to `XDG_CONFIG_DIRS`
  - runs `plasma-bigscreen-envmanager --apply-settings`

  [common-env](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/bin/plasma-bigscreen-common-env)
- **F45 runtime requires** include `libcec.so.8`, `libSDL3.so.0`, `libPlasma.so.8` and Qt 6.11 private API — [mdapi f45](https://mdapi.fedoraproject.org/f45/pkg/plasma-bigscreen)
- Fedora `libcec` is 7.1.1 on F43 — [mdapi](https://mdapi.fedoraproject.org/f43-updates/pkg/libcec)
- **BuildRequires for a from-source build** — [Fedora spec](https://src.fedoraproject.org/rpms/plasma-bigscreen/blob/rawhide/f/plasma-bigscreen.spec):
  - `extra-cmake-modules`, `kf6-rpm-macros`
  - KF6: I18n, Kirigami2, KCMUtils, Notifications, KIO, WindowSystem, Svg, BluezQt, GlobalAccel, DBusAddons, IconThemes, Screen, ItemModels
  - `cmake(Plasma)`, `PlasmaActivities`, `PlasmaActivitiesStats`, `PlasmaWaylandProtocols`, `LibKWorkspace`
  - `QCoro6`, `SDL3`, `pkgconfig(libcec)`, wayland-client/server/cursor/egl
  - Qt6 Quick, Qml, DBus, Network, Multimedia, WebEngineCore
  - `qt6qml(org.kde.kdeconnect)`
  - Build steps: `%cmake_kf6` then `%cmake_build`
- Aura 26.11.0 needs Qt6 WebEngineQuick plus KF6; Plank Player 26.11.0 needs Qt6 Multimedia plus KF6 — [aura CMakeLists](https://invent.kde.org/plasma-bigscreen/aura-browser/-/blob/master/CMakeLists.txt), [plank CMakeLists](https://invent.kde.org/plasma-bigscreen/plank-player/-/blob/master/CMakeLists.txt)
- The upstream README lists these runtime deps: plasma-nano, plasma-nm, plasma-pa, milou, libkscreen, kwin, KDE Connect — [README](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/README.md)
- **On-screen keyboard:** envmanager writes `kwinrc [Wayland] InputMethod=/usr/share/applications/org.kde.plasma.keyboard.desktop`, which is plasma-keyboard — [envmanager/config.h](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/envmanager/config.h)

### Inferences
- The Fedora RPM does not require plasma-keyboard, so the on-screen keyboard is probably missing unless you add it. Whether Fedora's package is named `plasma-keyboard` is UNVERIFIED.

### Gaps
- I did not check whether @kdesig or solopasha COPRs carry Bigscreen. They are unnecessary now that Fedora ships it.
- Aura and Plank were not found on Flathub (API 404s for the guessed IDs, and a search for "bigscreen" found nothing).
- Other Flathub IDs for them may exist. UNVERIFIED.

---

## Q3. Compatibility with Bazzite

### Takeaway
Bazzite stable **45.20261117.1** is built on `ghcr.io/ublue-os/kinoite-main:45` and ships **KDE 6.8.3-1 from Fedora**. That is an exact match for Fedora's `plasma-bigscreen-6.8.3-1.fc45`. The main risks are three:
- Bazzite **versionlocks `plasma-*` and `qt6-*`**.
- The login manager differs by image: **Plasma Login Manager** on desktop images, **SDDM** on deck images.
- The deck image installs `/etc/xdg` presets.

### Cited Findings
- **Release `45.20261117.1` (2026-11-17)** — [Bazzite release](https://github.com/ublue-os/bazzite/releases/tag/45.20261117.1):

  | Component | Version |
  |---|---|
  | Kernel | 7.3.4-ogc8.1 |
  | Nvidia LTS kernel | 6.18.60-ogc1.2 |
  | Mesa | 26.2.7 |
  | Gamescope | 3.17.0 |
  | Gamescope Session | 0~20261002git |
  | SteamOS-Manager | 0~20261031git |
  | KDE | 6.8.3-1 |
  | Nvidia Open | 620.70.06 |
  | Nvidia LTS | 580.196.07 |

- Testing and unstable streams are also on F45 — [releases](https://github.com/ublue-os/bazzite/releases)
- The Containerfile defaults to `BASE_IMAGE=ghcr.io/ublue-os/kinoite-main:45` and ends with `bootc container lint` — [Containerfile](https://github.com/ublue-os/bazzite/blob/main/Containerfile)
- **Versionlock:** "On Kinoite images, lock qt6 and plasma packages" runs `dnf versionlock add "qt6-*"` and `dnf versionlock add "plasma-*"`. The ublue-os/staging COPR excludes `kf6-*`, so KDE comes from Fedora — [04-initialize.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/04-initialize.sh)
- Bazzite already installs `libcec`, `linux-cec` and `inputattach-cec-units` — [07-install-packages.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/07-install-packages.sh)
- **Desktop KDE image changes** — [configure-kde.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite/desktop_env/configure-kde.sh):
  - installs `steamdeck-kde-presets-desktop`, krunner plugins and others
  - removes `plasma-drkonqi`, `plasma-welcome`, `plasma-discover*`, `plasma-setup`, `xwaylandvideobridge`
  - adds `bazzite-pins.js` to the `org.kde.plasma.desktop` panel layout only
- The desktop image ships `/usr/lib/plasmalogin/defaults.conf` (greeter wallpaper), so it uses **Plasma Login Manager** — [defaults.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/kinoite/usr/lib/plasmalogin/defaults.conf)
- **Deck image changes:**
  - **installs `sddm` and removes `plasma-login-manager`**
  - swaps in `steamdeck-kde-presets`, which installs `/etc/xdg/{kdeglobals,kwinrc,kcminputrc,kwinrulesrc,powerdevilrc,kscreenlockerrc,baloofilerc}` and `plasma-workspace/env/set-return-icon.sh`

  [01-configure-desktop.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/01-configure-desktop.sh); [steamdeck-kde-presets.spec](https://github.com/ublue-os/bazzite/blob/main/spec_files/steamdeck-kde-presets/steamdeck-kde-presets.spec)
- **Plasma Login Manager:**
  - It is a fork of SDDM.
  - User config lives in `/etc/plasmalogin.conf` and `/etc/plasmalogin.conf.d`.
  - The system drop-in dir is `/usr/lib/plasmalogin/plasmalogin.conf.d`.
  - Distro defaults go in `/usr/lib/plasmalogin/defaults.conf`, which "can be modified to set a default … login session".

  [PLM README](https://invent.kde.org/plasma/plasma-login-manager/-/blob/master/README.md), [PLM CMakeLists](https://invent.kde.org/plasma/plasma-login-manager/-/blob/master/CMakeLists.txt)
- **Config layering:**
  - Envmanager writes `~/.config/plasma-bigscreen/{kwinrc,kdeglobals,ksmserverrc,plasmakeyboardrc,applications-blacklistrc}` plus `~/.config/plasmabigscreenrc`.
  - It forces `LookAndFeelPackage=org.kde.plasma.bigscreen`, borderless maximized windows, `Placement=Maximizing`, blur off, KWin `gamecontrollerEnabled=false`, hidecursor on, virtual keyboard on, `TabletMode=off`, and ksmserver `loginMode=emptySession`.
  - That directory is prepended to `XDG_CONFIG_DIRS`.

  [envmanager/config.h](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/envmanager/config.h), [settings.cpp](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/envmanager/settings.cpp)
- **Open issues about sharing config between Desktop and Bigscreen:**
  - [#67 "Switching from Plasma Desktop: Feature disparity with logging in directly"](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/67)
  - [bko 524337 "Save display settings for session in a separate kwinoutputconfig.json"](https://bugs.kde.org/show_bug.cgi?id=524337)

### Inferences
- **Config precedence:**
  - The Bigscreen layer (`~/.config/plasma-bigscreen`) sits *above* `/etc/xdg`, so it overrides Bazzite's `/etc/xdg/kwinrc` and `kdeglobals` for the keys envmanager sets.
  - It sits *below* `~/.config/*rc`. Anything the user changed in a Desktop session, in the same key, still wins in Bigscreen. That is standard KConfig cascading, not tested here.
  - Display layout (`kwinoutputconfig.json`) is shared between sessions.
- **Versionlock persistence:** cleanup and finalize do not remove the versionlock, so it probably persists into derived images (UNVERIFIED).
  - Fedora's updates repo normally keeps only the newest build.
  - So if Fedora ships Plasma 6.8.4 before Bazzite rebases, `dnf5 install plasma-bigscreen` may fail on `plasma-workspace-wayland >= 6.8.4`.
- `bazzite-pins.js` and the desktop panel layout don't affect the Bigscreen shell.

### Gaps
- I could not open PLM's `Configuration.h` to confirm that it keeps SDDM's `[Autologin] User/Session/Relogin` keys.
- Prior art uses those keys successfully (see Q5).
- The exact appletsrc filename Bigscreen uses for its shell layout is UNVERIFIED.

---

## Q4. HTPC integration

### Takeaway
`bazzite-deck` already has what a two-mode TV box needs: SDDM autologin with `Relogin=true`, `steamosctl` session switching, and `gamescope-session-plus`. On top of it, Bigscreen can become the "desktop" session. A plain `bazzite` base only makes sense for a Bigscreen-only box that runs Steam Big Picture inside KWin.

### Cited Findings
- **Image variants:** `bazzite`, `bazzite-gnome`, `bazzite-deck`, `bazzite-deck-gnome`, `bazzite-deck-nvidia` and `bazzite-deck-nvidia-gnome`. NVIDIA variants use `nvidia-open` — [build.py](https://github.com/ublue-os/bazzite/blob/main/build.py)
- **Deck SDDM config** — [holo.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf):
  ```ini
  # /usr/lib/sddm/sddm.conf.d/holo.conf
  [General]
  DisplayServer=wayland
  [Autologin]
  Relogin=true
  Session=gamescope-session-ogui-steam.desktop
  ```
  A virtual keyboard is also configured: `/etc/sddm.conf.d/virtualkbd.conf` sets `InputMethod=qtvirtualkeyboard` — [file](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/etc/sddm.conf.d/virtualkbd.conf)
- Deck installs `gamescope-session-ogui-steam`, `steamos-manager-powerstation`, `inputplumber`, `qt6-qtvirtualkeyboard` and more from Terra. The Steam bootstrap goes to `/usr/share/gamescope-session-plus/` — [02-install-packages.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/02-install-packages.sh), [03-install-gamescope-session.sh](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/03-install-gamescope-session.sh)
- **Mode-switch commands:**
  - just recipes call `steamosctl set-default-login-mode game|desktop` — [95-bazzite-deck-session.just](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/share/ublue-os/just/95-bazzite-deck-session.just)
  - `/usr/libexec/os-session-select` is "deprecated … exists for Steam client compatibility". It **hardcodes `plasma.desktop`** on Kinoite and calls `steamosctl switch-to-desktop-mode plasma.desktop` — [os-session-select](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/os-session-select)
- SalongOS (built on bazzite-deck) uses `steamosctl set-default-desktop-session plasma-bigscreen-wayland.desktop` and `steamosctl set-default-login-mode desktop`, and reports that Steam's "Switch to Desktop" then lands in Bigscreen. Its Bigscreen "Steam" tile is rewritten to `Exec=steamosctl switch-to-game-mode` — [SalongOS README](https://github.com/MrCraigen/SalongOS), [build.sh](https://github.com/MrCraigen/SalongOS/blob/main/build_files/build.sh)
- **Plasma Login Manager autologin on desktop images** (as used by bifrost-htpc; bifrost substitutes `@USER@` at install time) — [bifrost-htpc](https://github.com/inklikeurine/bifrost-htpc/blob/main/files/etc/plasmalogin.conf.d/50-bifrost-autologin.conf):
  ```ini
  # /etc/plasmalogin.conf.d/50-autologin.conf
  [Autologin]
  User=<user>
  Session=plasma-bigscreen-wayland.desktop
  Relogin=true
  ```
- **Bazzite HTPC docs** — [quirks](https://docs.bazzite.gg/Handheld_and_HTPC_edition/quirks/):
  - Pick the output with `OUTPUT_CONNECTOR=` in `~/.config/environment.d/10-gamescope-session.conf`.
  - For HDMI audio, disable every sound device except HDMI.
  - On AMD, HDMI 2.1 FRL/VRR/DSC arrived with kernel 7.2 and is enabled with the Portal toggle "Enable HDMI 2.1 for AMD Graphics Cards" (may flicker).
  - From a TTY, `steamosctl switch-to-desktop-mode` recovers a stuck session.
  - OpenGamepadUI is off by default on HTPCs (`ujust configure-opengamepadui`).
- Bazzite's `ujust configure-htpc-auto-hdr` writes `gamescope_hdr_content_driven=true` to `~/.config/environment.d/90-gamescope-hdr.conf`. It applies to Gaming Mode only — [98-bazzite-htpc-auto-hdr.just](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/share/ublue-os/just/98-bazzite-htpc-auto-hdr.just)
- `plasma-bigscreen-swap-session` lets a running Plasma Desktop swap in place to the Bigscreen shell (`plasmashell --replace`) and back. Swap mode has feature gaps (#67) — [swap-session](https://invent.kde.org/plasma/plasma-bigscreen/-/blob/v6.8.3/bin/plasma-bigscreen-swap-session)
- An open feature issue, [#45 "homescreen: Console/gaming integration"](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/45), shows there is no native Steam integration yet.

### Inferences
- **Session-switch problem:** Steam may still call `os-session-select plasma`, and that would bypass the `steamosctl` default and drop users into Plasma Desktop instead of Bigscreen. To be safe, a derived image should override `/usr/libexec/os-session-select` to use `plasma-bigscreen-wayland.desktop`.
- On deck images, autologin should be driven by `steamosctl` (steamos-manager). Do not add a second `/etc/sddm.conf.d` `Session=` that fights it.
- **Controller input:** Steam Input virtual pads plus Bigscreen's SDL3 inputhandler can double events while Steam runs inside the Bigscreen session. Bigscreen's input suspension, or whitelisting ([bko 521903](https://bugs.kde.org/show_bug.cgi?id=521903)), is the mitigation. Switching to Gaming Mode avoids the problem entirely.
- **CEC permissions:** the upstream README says `usermod -aG input`/`dialout`. On Atomic images, groups that exist only in `/usr/lib/group` have to be copied into `/etc/group` first (UNVERIFIED for Bazzite; it has ujust helpers for similar cases).

### Gaps
- I could not open steamos-manager's source to confirm where it stores the default desktop session. SalongOS says the settings are per-user and survive updates.
- I did not find where `User=` is set for the deck SDDM autologin.

---

## Q5. Prior art

### Takeaway
At least seven recent ublue, bootc or Kinoite projects ship Bigscreen. All of them simply `dnf5 install plasma-bigscreen plasma-bigscreen-wayland` from Fedora; none builds from source.

### Cited Findings
- **[MrCraigen/SalongOS](https://github.com/MrCraigen/SalongOS)** (pushed 2026-11-14)
  - Built `FROM ghcr.io/ublue-os/bazzite-deck:stable` with the image-template.
  - Installs Bigscreen, repoints the Steam tile to Gaming Mode, and removes `opengamepadui.desktop` because "Bigscreen ignores NoDisplay/Hidden".
  - Says NVIDIA is untested.
- **[anderstvoss/bazzite-bigscreen](https://github.com/anderstvoss/bazzite-bigscreen)** (2026-11-08): `FROM ghcr.io/ublue-os/bazzite:stable@sha256…` plus the same two packages.
- **[douglascdev/blueHTPC](https://github.com/douglascdev/blueHTPC)** (2026-10-02)
  - A BlueBuild recipe on `kinoite-main`, adding Flatpaks (Kodi, Plex HTPC, Stremio, VacuumTube, Bazaar).
  - A firstboot script writes a PLM autologin config. It has a bug: it `mkdir`s `/etc/sddm.conf.d` but writes to `/etc/plasmalogin.conf.d` — [script](https://github.com/douglascdev/blueHTPC/blob/main/files/usr/libexec/firstboot-autologin.sh)
- **[inklikeurine/bifrost-htpc](https://github.com/inklikeurine/bifrost-htpc)** (2026-11-18)
  - Layers packages onto Kinoite and uses PLM autologin.
  - Adds a WirePlumber rule that prefers HDMI profiles.
  - Notes that "Bigscreen 6.7.5 needs a newer Plasma than the 44.1.7 ISO's 6.6.4", which shows the version-skew risk — [wireplumber conf](https://github.com/inklikeurine/bifrost-htpc/blob/main/files/etc/wireplumber/wireplumber.conf.d/50-bifrost-tv-audio.conf)
- **Other projects:**
  - [shawly/ublue-atomc](https://github.com/shawly/ublue-atomc): Kinoite plus Bigscreen plus Kodi GBM, 2026-08
  - [ChristophKloos/Kino](https://github.com/ChristophKloos/Kino): WIP, 2026-09
  - [edermats32/plasma-bigscreen-minimal-fedora](https://github.com/edermats32/plasma-bigscreen-minimal-fedora): 2026-10
  - [TheNoswad/plasma-bigscreen-immutable](https://github.com/TheNoswad/plasma-bigscreen-immutable): 2026-01
  - [AeroCore-IO/AeroCore-OS](https://github.com/AeroCore-IO/AeroCore-OS): Bazzite HTPC
  - [boredsquirrel/Fedora-TV-KDE-Bigscreen](https://github.com/boredsquirrel/Fedora-TV-KDE-Bigscreen): **stale, 2023, Plasma 5/Mycroft era**
- **Other distros:**
  - Arch `extra/plasma-bigscreen` 6.8.3 (updated 2026-11-15) — [Arch](https://archlinux.org/packages/extra/x86_64/plasma-bigscreen/)
  - AUR `plank-player` 26.11.0-1 — [AUR](https://aur.archlinux.org/packages/plank-player)
  - AUR `aura-browser` is **stale at 5.27.11-1** — [AUR](https://aur.archlinux.org/packages/aura-browser)
  - The project's get page lists Fedora (no dedicated edition), Arch, Nura (formerly postmarketOS; pmbootstrap, no ISO), NixOS, Void, and KDE neon (dev builds plus an x86-64 test image) — [plasma-bigscreen.org/get](https://plasma-bigscreen.org/get/)
  - KDE has a Debos RPi4 image repo, active 2026-11-05 — [bigscreen-debos-image-rpi4](https://invent.kde.org/plasma-bigscreen/bigscreen-debos-image-rpi4)

### Gaps
- KDE Linux and openSUSE are not listed on the get page. I did not query openSUSE OBS.

---

## Q6. Known issues

### Takeaway
Bigscreen works but is young. The gaps that matter for a TV box:
- CEC depth: AVR volume, the TV holding Back/Home, init options
- auto-sleep, notifications, and on-screen keyboard navigation with a TV remote
- no app store or first-run wizard
- HDR and VRR are whatever KWin gives you; there is no gamescope-style auto-HDR

NVIDIA is largely untested in this combination.

### Cited Findings
- **Open GitLab issues** — [issues list](https://invent.kde.org/plasma/plasma-bigscreen/-/issues):
  - [#57](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/57): on-screen keyboard can't be navigated with only a TV remote
  - [#59](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/59): `40-uinput.rules` won't work on systemd distros
  - [#73](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/73): CEC init behaviour
  - [#56](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/56): deeper CEC integration
  - [#64](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/64): IR remotes
  - [#69](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/69): display-scaling slider bug
  - [#70](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/70): inputhandler as a service
  - [#72](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/72): honour `X-KDE-FormFactors`
  - [#43](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/43): app store
  - [#44](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/44): first-run wizard
  - [#63](https://invent.kde.org/plasma/plasma-bigscreen/-/issues/63): Nintendo controller mappings reversed
- **Bugzilla:**
  - [523726](https://bugs.kde.org/show_bug.cgi?id=523726): CEC volume never reaches an AV receiver
  - [524711](https://bugs.kde.org/show_bug.cgi?id=524711): system never auto-sleeps
  - [522754](https://bugs.kde.org/show_bug.cgi?id=522754): no notifications
  - [523725](https://bugs.kde.org/show_bug.cgi?id=523725): gamepad control is not returned to the homescreen after leaving an app
  - [529010](https://bugs.kde.org/show_bug.cgi?id=529010): homescreen won't launch an app that has multiple windows
  - [518977](https://bugs.kde.org/show_bug.cgi?id=518977): Aura on-screen typing
  - [452747](https://bugs.kde.org/show_bug.cgi?id=452747): `plasma-apply-wallpaperimage` fails
- Upstream docs warn that CEC is implemented inconsistently across TVs and that most PCs need an adapter — [docs/inputs](https://plasma-bigscreen.org/docs/inputs/)
- **HDR and VRR:**
  - Plasma 6.7: ICC color management and HDR can be used together — [6.7.0](https://kde.org/announcements/plasma/6/6.7.0/)
  - Plasma 6.8: NVIDIA HDR improvements with ICC, plus HLG — [6.8.0](https://kde.org/announcements/plasma/6/6.8.0/)
  - Bazzite: AMD HDMI 2.1/VRR needs the Portal toggle and may flicker; HDMI audio needs the default device fixed by hand — [quirks](https://docs.bazzite.gg/Handheld_and_HTPC_edition/quirks/)

### Inferences
- In the Bigscreen session, content-driven HDR switching, which is gamescope-only, is unavailable. Neither is any refresh-rate or frame-rate matching I could find.
- 4K scaling is set through KScreen and is shared with the Desktop session (#69, bko 524337).
- On NVIDIA, use the `bazzite-deck-nvidia` base. Expect less testing.

### Gaps
- I found no reliable reports specific to NVIDIA with Bigscreen, and no CEC wake-on-resume behaviour documentation.
- A web search for TV, HDR and NVIDIA Bigscreen problems returned only TV-hardware reviews.

---

## Recommendation

**Base image**
- Use **`ghcr.io/ublue-os/bazzite-deck:stable`** for AMD or Intel, and **`bazzite-deck-nvidia:stable`** for NVIDIA.
  - It keeps Gaming Mode, SDDM `Relogin`, `steamosctl` and the gamescope HDR/VRR handling, and adds Bigscreen as the desktop session (the SalongOS model).
- Use plain `bazzite` (Plasma Login Manager) only for a Bigscreen-only box. Autologin would then go through `/etc/plasmalogin.conf.d/*.conf`, with the user written at first boot.

**Build steps (deck base)**
```bash
# build_files/build.sh
PV=$(rpm -q --qf '%{VERSION}' plasma-workspace)       # match Bazzite's versionlocked Plasma
dnf5 -y install "plasma-bigscreen-${PV}" "plasma-bigscreen-wayland-${PV}" plasma-keyboard  # plasma-keyboard name UNVERIFIED
# Make Steam's "Switch to Desktop" land in Bigscreen
sed -i 's/desktop_session="plasma.desktop"/desktop_session="plasma-bigscreen-wayland.desktop"/' /usr/libexec/os-session-select
# Bigscreen "Steam" tile -> Gaming Mode (SalongOS approach)
sed -i 's|^Exec=/usr/bin/bazzite-steam %U$|Exec=steamosctl switch-to-game-mode|' /usr/share/applications/steam.desktop
rm -f /usr/share/applications/opengamepadui.desktop
```

**Rules for the build**
- Keep `bootc container lint`.
- Fail the build if `plasma-bigscreen` and `plasma-workspace` versions differ. This guards against Fedora moving ahead of Bazzite's lock.
- Default users to Bigscreen through `steamosctl set-default-desktop-session plasma-bigscreen-wayland.desktop` plus `set-default-login-mode desktop`, run once per user (for example from a first-login autostart). Don't bake `Session=` into `/etc/sddm.conf.d`.
- Add a WirePlumber HDMI-priority drop-in (bifrost snippet).
- Aura and Plank Player are not in Fedora:
  - Either build them in a multi-stage `fedora:45` builder (KF6, Qt6 WebEngineQuick/Multimedia, `cmake -DCMAKE_INSTALL_PREFIX=/usr`, `DESTDIR` install, copy into the image),
  - or override `BrowserApplication` to Firefox/Chromium.
- Build Bigscreen itself from source only if the Fedora RPM ever lags the locked Plasma version. The spec's BuildRequires above are the dependency list.
