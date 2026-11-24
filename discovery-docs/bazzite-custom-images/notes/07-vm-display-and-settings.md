# SwayFX in the test VM: display settings, auto-resize, cursor (2026-11-23)

The user found three problems testing `bazzite-swayfx-nvidia` in virt-manager:
- no app to set screen resolution or layout under sway
- the screen doesn't follow the virt-manager window size
- the mouse pointer is drawn upside down and offset

## Test VM facts (checked through the guest agent)

- SwayFX 0.6.1 (sway 1.12, wlroots 0.20, scenefx 0.5). Output `Virtual-1`, 1280x800 (the
  virtio-gpu default), 26 modes.
- libvirt: `virtio` video with `accel3d`, Spice with GL on renderD128 (i915). virt-install added a
  `spicevmc` channel (`com.redhat.spice.0`), and its state is `connected`, so spice-vdagentd runs
  in the guest.
- Host: libvirt 12.2, **QEMU 10.2.4**.
- `spice-vdagent.service` (user) is `PartOf=graphical-session.target`. sway-systemd's
  `sway-session.target` binds that target, so it runs under sway too.

## Fedora's start-sway on KVM

`/usr/bin/start-sway` (sway-config-fedora) checks `systemd-detect-virt --vm`:

| Virtualisation | What start-sway sets |
|---|---|
| none | nothing |
| `kvm` | `WLR_RENDERER=pixman`, `WLR_DRM_NO_ATOMIC=1`. Its comment says no `WLR_NO_HARDWARE_CURSORS` is needed with legacy DRM |
| any other VM | `WLR_NO_HARDWARE_CURSORS=1` (sway#6581) |

**SwayFX ignores `WLR_RENDERER`.** `sway/server.c` in 0.6.1 calls `fx_renderer_create(backend)`
(GLES), not `wlr_renderer_autocreate`, and only `wlr_renderer_autocreate` reads that variable. So on
KVM, SwayFX renders with OpenGL through virgl, using legacy KMS and a hardware cursor plane.

Next in its order, start-sway sources `/etc/sway/environment` with `set -o allexport`. This is a
Fedora `%config` file, and it is where a system-wide extra variable belongs.

## Cursor upside down: a QEMU bug, worked around in the guest

- [QEMU issue 2315](https://gitlab.com/qemu-project/qemu/-/issues/2315): with virtio-gpu-gl, a cursor
  the guest renders with OpenGL is a resource flagged `Y_0_TOP`, and QEMU passes it to the display
  without flipping. The cursor appears upside down, so its tip (hotspot) also looks offset. This
  affects sway, wayfire, Hyprland and KWin 6.0.4.
- Fix patches were posted in April 2026:
  [v1](https://patchew.org/QEMU/20260409144639.3610-1-benno.fuenfstueck@neodyme.io) and
  [v2](https://patchew.org/QEMU/20260427105531.75701-1-benno.fuenfstueck@neodyme.io/), the latter
  gated on the virglrenderer version. The host's QEMU 10.2.4 predates them.
- KDE equivalents: [KDE bug 486239](https://bugs.kde.org/show_bug.cgi?id=486239),
  [509339](https://bugs.kde.org/show_bug.cgi?id=509339) and
  [Red Hat bug 2112635](https://bugzilla.redhat.com/show_bug.cgi?id=2112635); the usual fix is a
  software cursor (`KWIN_FORCE_SW_CURSOR=1`).
- **Image fix:** `/etc/sway/environment` sets `WLR_NO_HARDWARE_CURSORS=1` when
  `systemd-detect-virt --quiet --vm`. wlroots then draws the pointer into each frame, so QEMU never
  sees a cursor resource. Bare metal is unaffected.

## Auto-resize: wlroots ignores new modes on a connected screen

How the resize reaches the guest:
1. With "Auto resize VM with window" on, virt-manager (spice-gtk) sends the window size as
   `VD_AGENT_MONITORS_CONFIG`.
2. spice-server hands it to QEMU (`client_monitors_config`, then `dpy_set_ui_info`), not to the
   guest agent.
3. virtio-gpu raises `VIRTIO_GPU_EVENT_DISPLAY`. The guest kernel re-reads the display info and EDID
   and sends a DRM hotplug uevent.
4. The connector has `hotplug_mode_update=1`, which means the mode list and preferred mode can change
   after a uevent. KWin and mutter re-read the modes and switch to the new preferred one.

What wlroots does instead:
- **wlroots 0.20 doesn't act on it.** `scan_drm_connectors()` in `backend/drm/drm.c` calls
  `drmModeGetConnector()`, which as DRM master makes the kernel re-probe and update its mode list.
  But for a connector that is connected both before and after, it does nothing: there's no
  mode-list update and no `request_state`. Only connect and disconnect are handled.
- Sway [PR #5942](https://github.com/swaywm/sway/pull/5942) (re-apply the config when the modes
  change, only where `hotplug_mode_update=1`) was closed in favour of wlroots PR #2712 ("respond to
  changed modes on DRM connectors"). The 0.20 code shows that never landed.
- Sway's own `handle_request_state` would apply a requested mode, but the DRM backend never sends
  one for this.

Checks in the VM:
- `swaymsg -- output Virtual-1 mode --custom 1600x900` works on virtio-gpu (`mode_valid` accepts
  32..8192). The `--` is needed, or swaymsg treats `--custom` as its own option.
- The kernel lists the preferred mode first in `/sys/class/drm/cardN-Virtual-M/modes`
  (`drm_mode_sort`), for example `1280x800`.

**Image fix:** `sway-vm-autoresize.service` is a user unit with `ConditionVirtualization=vm`, bound
to `sway-session.target`. It runs `/usr/libexec/sway-vm-autoresize`, which:
- watches `udevadm monitor --udev --subsystem-match=drm`;
- after each burst of events, waits 0.5 s of quiet (sway has re-probed by then);
- reads the first line of each connected `Virtual-*` connector's `modes`;
- runs `swaymsg -- output NAME mode --custom WxH` when that size differs from the last one it applied.

## Display settings app under sway

KDE's display settings (KScreen) need KWin's output-device protocol and can't drive sway.

Options in Fedora 45 and Terra (repoquery from the built image):

| Tool | Repo | Saves settings | Notes |
|---|---|---|---|
| nwg-displays 0.5.0 | Terra | yes: `~/.config/sway/outputs` and `~/.config/sway/workspaces`, used with `include` | GTK3 drag-and-drop layout, mode, scale, rotation, workspace-to-output. 422 KiB; all its deps (python3-i3ipc, gtk-layer-shell, pygobject) are already in the image |
| wdisplays 1.3.0 | Fedora | no (live only; needs kanshi to persist) | 212 KiB |
| kanshi 1.9.0, wlr-randr 0.5.0 | Fedora | kanshi profiles | no GUI |

Noctalia 5.x has no built-in sway output editor. noctalia.dev lists plugins:
[Monitor Layout](https://noctalia.dev/plugins/monitor-layout) (sway and Hyprland, applies through
swaymsg) and [Display Settings](https://noctalia.dev/plugins/display-settings) (editable only on
Niri). Users can add those themselves.

**Choice: nwg-displays.**
- It's added to the Terra `includepkgs`.
- Its desktop entry ("Displays Settings") gets `OnlyShowIn=sway;`, because it exits with "Neither
  sway, Hyprland, niri nor Mango detected" under Plasma.
- `/etc/sway/config` includes `$HOME/.config/sway/outputs` and `$HOME/.config/sway/workspaces`.
  A missing file is skipped, as with the Noctalia colours include.

## Build verification (image 37688d89ec1d)

- **Build:**
  - `just build bazzite-swayfx-nvidia` succeeded, and `bootc container lint` passed 14 checks.
  - RPM wrote `.rpmnew` copies for both `/etc/sway/config` and `/etc/sway/environment`; the build
    removes them after checking that ours won.
  - nwg-displays 0.5.0 installed, and its desktop entry has `OnlyShowIn=sway;`.
  - `/etc/systemd/user/sway-session.target.wants/sway-vm-autoresize.service` exists.
- **`/etc/sway/environment`:** passes `sh -n`. Sourced as start-sway does, it sets no `WLR_`
  variable on bare metal. With a stub `systemd-detect-virt` that exits 0, it sets
  `WLR_NO_HARDWARE_CURSORS=1`.
- **Resize script test:** a fake `/sys/class/drm` was bind-mounted in, with stub `udevadm` and
  `swaymsg`.
  - The udevadm header lines are ignored.
  - A burst of three events gives one `output Virtual-1 mode --custom 1600x900`.
  - A repeat event at the same size gives no call.
  - A changed `modes` file gives `--custom 1920x1080`.
  - The disconnected connector is skipped, and the script exits 0 at EOF.
- **Config:** `sway --validate` (needs `--device /dev/dri/renderD128`, since SwayFX can't create its
  GLES renderer without a DRM device):
  - no errors without the nwg-displays files, and none with valid `outputs` and `workspaces` files;
  - a bad line in `outputs` is reported from that file, so the include is read.

Still to check in the VM: the pointer orientation, resizing when the window changes (with *Auto
resize VM with window* on), and that Displays Settings keeps a saved mode across logins.

## Sources

- https://gitlab.com/qemu-project/qemu/-/issues/2315
- https://patchew.org/QEMU/20260427105531.75701-1-benno.fuenfstueck@neodyme.io/
- https://bugzilla.redhat.com/show_bug.cgi?id=2112635
- https://github.com/swaywm/sway/pull/5942
- https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.20/backend/drm/drm.c (`scan_drm_connectors`)
- https://raw.githubusercontent.com/wlrfx/swayfx/0.6.1/sway/server.c and `sway/desktop/output.c`
- https://github.com/nwg-piotr/nwg-displays (README v0.5.0)
- https://noctalia.dev/plugins/monitor-layout, https://noctalia.dev/plugins/display-settings

## Disk build: the second sudo prompt (2026-11-23)

`just build-qcow2` timed out on credentials again. The template's `_rootful_load_image` dependency
made its own `sudo podman image scp` call to copy the 12 GB image into root's storage, which took
about 6 minutes (08:38 to 08:44). The cache started when that sudo did, so the single
`sudo bash` for bootc-image-builder found the 5-minute `timestamp_timeout` expired and prompted
again. The build gave up after the 5-minute `passwd_timeout` (08:44:43 to 08:49:48).

**Fix:** `_rootful_load_image` was removed. `_build-bib` now does the whole job in its one
`sudo bash -c`:
1. Compares the image ID in your storage (read as you, before sudo) with root's copy.
2. Runs `podman image scp UID@localhost::IMG root@localhost::IMG` when they differ, or `podman pull`
   when you don't have the image. `TMPDIR` points at a user-owned `_build_podman_scp.*` folder.
3. Runs bootc-image-builder, then the copy-out and chown.

Tested with stub `sudo` and `podman` in a scratch folder. All three cases (copy, skip, pull) make
exactly one sudo call, remove both temporary folders and the password-bearing config, and write
`output/<image>/qcow2/disk.qcow2`.

## Displays Settings didn't start (VM test, 2026-11-23)

The user saw "Displays Settings" in the Noctalia launcher, but it didn't open.

- **Cause:** `nwg_displays/main.py` (0.5.0, lines 62–68) exits with status 1 and prints
  "Couldn't find sway config directory" when `$XDG_CONFIG_HOME/sway` (by default `~/.config/sway`)
  is missing. A fresh user has no `~/.config/sway`, because sway falls back to `/etc/sway/config`.
- **Reproduced** through the guest agent. It ran as root against the user's sway and Wayland
  sockets, with `GSETTINGS_BACKEND=memory` (dconf's shm mmap fails in the agent's SELinux domain).
  - Without the folder, it exits 1 with that message.
  - With the folder, it reads the outputs and builds its window. It then aborts loading an icon
    with a gdk-pixbuf/glycin "Seccomp" error, which is the agent's confinement (glycin sandboxes
    its loaders), not the user session.
- **Fix:** `/usr/share/user-tmpfiles.d/sway-config-dir.conf` with `d %h/.config/sway - - - -`. The
  user `systemd-tmpfiles-setup.service` is enabled globally (`basic.target.wants`), so it runs at
  every login, and it also covers accounts that existed before rebasing (`/etc/skel` would only
  cover new ones). Mode `-` and age `-` leave an existing folder's mode and contents alone.
- **systemd 262 tmpfiles has no `%E`** (config home) specifier: it fails with "Invalid slot". So the
  rule uses `%h/.config`.
- **Tested** as uid 1000 in the image: it creates the folder at 0755; an existing 0700 folder with an
  `outputs` file is unchanged, even with `--clean`.
