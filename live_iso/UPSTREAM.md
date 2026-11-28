# Upstream code in live_iso/

`just build-live-iso` builds a live USB installer the way Bazzite builds its own ISOs. The
upstream code it runs is in two git submodules, pinned to exact commits and not modified:

| Submodule | Source | What the build uses | Licence |
|---|---|---|---|
| `bazzite/` | [ublue-os/bazzite](https://github.com/ublue-os/bazzite) | `installer/` | Apache-2.0 (`bazzite/LICENSE`) |
| `titanoboa/` | [ublue-os/titanoboa](https://github.com/ublue-os/titanoboa) | `build_iso.sh` | Apache-2.0 (`titanoboa/LICENSE`) |

- `git submodule status` shows the pinned commits.
- `build-info.txt` next to each ISO records the commits it was built from.
- The recipe checks the submodules out if they're missing. To do it yourself:
  `git submodule update --init --depth 1`.
  - Keep `--depth 1`. `shallow = true` in `.gitmodules` only shallows the first clone of `main`.
    Fetching a pinned commit that isn't `main`'s tip then downloads Bazzite's whole history:
    about 300 MB instead of 100 MB.
  - Leave out `--recursive`: Bazzite's own submodules aren't needed.
- A checkout has only the pinned commit. The upstream history is on GitHub, for example
  `https://github.com/ublue-os/bazzite/commits/<commit>/installer`.

Our own files sit next to them:
- `build-live-root.sh`: runs `trust-payload.sh`, then Bazzite's `build.sh`, in a container (not
  `podman build`) that becomes the USB's filesystem. It replaces Bazzite's
  `installer/Containerfile`, which isn't used. Committing a ~25 GB layer would briefly need about
  three copies of it on disk.
- `trust-payload.sh`: makes the build's `podman pull` require our cosign signature on the payload.
- `iso.yaml.in`: our boot menu. It replaces Bazzite's `iso.yaml` in the build.

Titanoboa's `main.sh` isn't used. It only runs `sudo podman run … quay.io/fedora/fedora:latest
/src/build_iso.sh`, which the recipe does itself: rootless, with a pinned Fedora image.

## Updating

Dependabot opens a pull request each month that moves a submodule to the newest commit on its
`main`. Bazzite's `main` changes daily, mostly outside `installer/`, so check what changed in the
files the build uses before merging. You can also bump a submodule by hand: Titanoboa is best kept
at the commit Bazzite's `.github/workflows/build_iso.yml` pins.

Claude comments on each Dependabot pull request (`.github/workflows/dependabot-review.yml`). For a
submodule bump, `.github/scripts/submodule-bump-context.sh` diffs the files the build uses (the
table above) and Bazzite's Titanoboa pin, and Claude summarises that against our files. Its comment
is a starting point: the steps below still apply when the files the build uses change.

1. Fetch both commits and review the change:
   ```bash
   git -C live_iso/bazzite fetch --depth 1 origin <old> <new>
   git -C live_iso/bazzite diff <old> <new> -- installer/
   ```
   For Titanoboa, use `-- build_iso.sh`. An empty diff means the bump doesn't change the build.
2. To bump by hand: `git -C live_iso/bazzite checkout --detach <new>`, then
   `git add live_iso/bazzite` and commit.
3. Build and test the ISO in a VM before using it.
