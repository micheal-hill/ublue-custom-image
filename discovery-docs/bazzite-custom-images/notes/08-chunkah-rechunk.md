# Rechunking with chunkah to keep the image labels (2026-11-24)

## Problem

The first published images (CI run 45372269275) had none of the labels that `just build` sets:
`org.opencontainers.image.{title,description,version,source,url,documentation,vendor,created}`
and the `io.artifacthub.package.*` set. Their config only held `containers.bootc`,
`ostree.commit` and `ostree.final-diffid`.

The cause is the template's rechunk step, `just ostree-rechunk`. It runs
`rpm-ostree compose build-chunked-oci --bootc --rootfs … --output containers-storage:…`, which
writes a new image from the root filesystem alone. Its docs
(https://coreos.github.io/rpm-ostree/build-chunked-oci/) list no option to carry over or set labels.

Without the labels:
- `bootc status` shows no version for the image;
- the GHCR package page has no description;
- nothing in the image links back to the commit it was built from.

## chunkah

https://github.com/coreos/chunkah is a distro-independent rechunker. The image-template ships it as a
commented-out workflow step plus a `rechunk` Justfile recipe.

**Status:**
- v0.7.1 is the latest release (October 2026).
- `quay.io/coreos/chunkah:latest` and `:v0.7.1` both point at
  `sha256:71e593421c5de7dcc7c8c5c50e98d3bac572055a76f399f61a491d123c20a523`. Tags are listed by
  quay's API: `https://quay.io/api/v1/repository/coreos/chunkah/tag/`.
- The README dropped its "experimental" notice in v0.4.0.

**Keeping the config and labels:**
- `--config FILE` (or `--config-str` / `CHUNKAH_CONFIG_STR`) takes an OCI image config. The output
  of `podman inspect` is also accepted and carries annotations too.
- `--label KEY=VALUE` adds a label, and `--label KEY-` removes one (since v0.2.0). `--annotation`
  sets annotations.
- In the `FROM oci:` build-time flow, the base labels are lost, including `containers.bootc=1`,
  which bootc needs. Pass the config in that flow too.

**bootc images:**
- chunkah has no special handling for them.
- For an image built on an ostree base, pass `--prune /sysroot/` to drop the ostree repo, and remove
  the stale `ostree.commit` and `ostree.final-diffid` labels. Since v0.4.0 it warns when
  `/sysroot/ostree` is left in.

**Other flags:**
- `--max-layers`: default 64. containers-storage allows at most 500.
- `--compressed`: gzip.
- `--output oci:DIR`: writes an OCI directory layout, which avoids a tar round trip (since v0.6.0).
  There's no containers-storage output; import the result with `podman pull oci:DIR`.

**Running it:**
- It runs without `--privileged`. The image is mounted with `--mount=type=image,…,target=/chunkah`.
- It needs room for a complete copy of the image, because the chunked image shares no layers with
  the original.

**Signing:**
- The images are cosign keyless-signed in the new bundle format, which needs **cosign v3+**.
  The distrobox's cosign (`devel`, a 2.x build) reports "no signatures found".
- Verify with:
  ```
  cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --certificate-identity-regexp '^https://github\.com/coreos/chunkah/' quay.io/coreos/chunkah:latest
  ```

## Universal Blue usage (checked 2026-11-24)

- **Bazzite** (`build.py` `cmd_rechunk`, `.github/workflows/build.yml` "Run Chunkah"):
  - Installs cosign before the rechunk step on every build (PRs too), and cosign-verifies the
    chunkah image by digest.
  - Passes `podman image inspect` output as `--config` (the comment there: it "Carries Env, Cmd, and
    containers.bootc over").
  - Adds its final labels with `--label`, and removes `ostree.commit` and `ostree.final-diffid`.
  - Uses `--max-layers 256`, `--prune /sysroot/` and `--prune /run/`, after emptying /run and /tmp
    in the raw image.
  - Sets `user.component` xattrs in `finalize.sh` to group files into layers.
- **Aurora** (`Justfile`, `image-versions.yml`): pins `quay.io/coreos/chunkah:latest@sha256:71e5…`
  (the v0.7.1 digest, kept current by Renovate). Its flags match the template's, plus `--prune /run/`
  and `--max-layers 256`.
- **image-template main**: the same `rechunk` recipe and commented-out step as our copy.

## Local test (2026-11-24)

I ran `just rechunk bazzite-bigscreen chunktest` with the host's rootless podman on a copy of the
local `bazzite-bigscreen` image, built 2026-11-22 from a dirty tree. It took about 6 minutes on the
laptop.

| | Original | Rechunked |
|---|---|---|
| Layers | 258 | 128 |
| Size | 12.18 GB | 12.18 GB |
| RPMs / files under /usr and /etc | 2722 / 280228 | 2722 / 280228 |
| `sudo` setuid, `newuidmap` `cap_setuid=ep` | kept | kept |
| Cmd, Env | kept | kept |
| `bootc container lint` | | 14 passed, 1 skipped |

**Labels:** every label carried over, except the ones removed with `--label KEY-`.

**Inherited base labels** (Bazzite builds with chunkah, so its images have no `ostree.commit`):
- Correct as inherited: `containers.bootc`, `ostree.bootable` and `ostree.linux`. We don't change
  the kernel, so `ostree.linux` still holds.
- Replaced by `just build`, but only in a clean tree (CI):
  - `org.opencontainers.image.{source,url,version,documentation}`
  - `io.artifacthub.package.readme-url`
- Stale and never replaced:
  - `org.opencontainers.image.revision`, which held Bazzite's commit. `just build` now sets it to
    our full SHA in a clean tree.
  - `rpmostree.inputhash`, Bazzite's build hash.
  - `quay.expires-after: 4w`, which only means something on Quay.

  The rechunk step now removes the last two. A second test run showed both removed and everything
  else unchanged.

## Decision

- Switch CI from `just ostree-rechunk` to `just rechunk`.
- Keep the template's flags, and also remove the two stale base labels.
- Set `org.opencontainers.image.revision` in clean-tree builds.
- Pin chunkah to `v0.7.1@sha256:71e5…` in the Justfile (`chunkah_image`). Dependabot only watches
  GitHub Actions here, so bump the pin by hand from the chunkah releases.
- Install cosign before rechunking and verify the pinned image in CI, as Bazzite does.
- The first CI run after the switch builds new layers. Nothing is installed from the registry yet,
  so no update pays the cost of a full re-download.
