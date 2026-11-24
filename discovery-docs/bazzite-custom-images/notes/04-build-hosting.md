<!-- Research notes gathered 2026-11-22 by a research subagent (web + GitHub/registry APIs). -->

# Building and hosting custom Bazzite/bootc images (alternatives to GitHub Actions + GHCR), as of 2026-11-22

Research notes. All pages were fetched on 2026-11-22 unless a date is given. I measured the Bazzite manifests myself with anonymous read-only GETs to ghcr.io; that is the only first-hand data here. Everything else comes from the linked pages.

**Measured baseline:** `ghcr.io/ublue-os/bazzite:stable` and `bazzite-nvidia:stable` are version `45.20261117.0`, created 2026-11-17. Each has 256 `tar+zstd` layers. The compressed size is 4.45 GB for bazzite and 4.90 GB for bazzite-nvidia. I did not measure uncompressed size; it is UNVERIFIED (one third-party article says Bazzite is an 11.6 GB image, [computingforgeeks](https://computingforgeeks.com/fedora-vs-bazzite/)).

---

## Q1. Local builds and getting the image onto targets without a public registry

### Takeaway
Local builds are fully supported. `sudo just build` puts the image straight into root's containers-storage, and `bootc switch --transport containers-storage` boots it. For a second machine you need either a file transport (`oci` or `oci-archive`) or a LAN registry. Only the LAN registry gives normal, hands-off `bootc upgrade` and uupd behaviour on the remote client.

### Cited findings
**image-template prerequisites and build**
- The Justfile needs `just`, `podman` and `jq`, which are "usually preinstalled on Universal Blue images". So you can build on a Bazzite host itself ([image-template README](https://github.com/ublue-os/image-template)).
- The README recommends `sudo just build` because it builds directly as root and skips the copy into root's storage. It documents `sudo bootc switch --transport containers-storage localhost/myimage:latest` ([README](https://github.com/ublue-os/image-template)).
- `just build` runs `podman build --pull=newer --tag "${target_image}:${tag}" --file Containerfile` ([Justfile](https://raw.githubusercontent.com/ublue-os/image-template/main/Justfile)).
- After a rootless build, the recipes call `_rootful_load_image`, which runs `podman image scp ${UID}@localhost::IMG root@localhost::IMG` ([Justfile](https://raw.githubusercontent.com/ublue-os/image-template/main/Justfile)).

**Rechunking (two recipes)**
- `just ostree-rechunk` runs `podman run --privileged … rpm-ostree compose build-chunked-oci --max-layers 127 --format-version=2 --bootc`. It uses a tmpfs at `/run/rpm-ostree-storage` and writes back into host containers-storage ([Justfile](https://raw.githubusercontent.com/ublue-os/image-template/main/Justfile)).
- `just rechunk` uses `quay.io/coreos/chunkah:latest` (unpinned) with `--max-layers 128`, then `podman pull oci:…` ([Justfile](https://raw.githubusercontent.com/ublue-os/image-template/main/Justfile)).
- chunkah describes itself as "a generalized successor to rpm-ostree's build-chunked-oci". Its default is 64 layers, it recommends 128 for bootc, and it notes that containers-storage has a hard limit of 500 layers ([coreos/chunkah](https://github.com/coreos/chunkah)).
- The template's CI still uses `just ostree-rechunk`; the chunkah path is commented out ([build.yml](https://raw.githubusercontent.com/ublue-os/image-template/main/.github/workflows/build.yml)).

**ISO and disk images**
- `just build-iso`, `build-qcow2` and `build-raw` all call `sudo podman run --rm -it --privileged --pull=newer --net=host --security-opt label=type:unconfined_t -v /var/lib/containers/storage:/var/lib/containers/storage … --type iso --use-librepo=True --rootfs=btrfs`. This is rootful and privileged ([Justfile](https://raw.githubusercontent.com/ublue-os/image-template/main/Justfile)).
- The bootc-image-builder source code now lives in `osbuild/image-builder`. The old repo only holds build configs for `quay.io/centos-bootc/bootc-image-builder` ([osbuild/bootc-image-builder](https://github.com/osbuild/bootc-image-builder)).
- Titanoboa builds live ISOs from bootc images. Run locally, it needs `sudo` and podman with `--cap-add sys_admin --security-opt label=disable`. There is also a GitHub Action, `ublue-os/titanoboa@main` ([titanoboa](https://github.com/ublue-os/titanoboa)).

**Transports and auth**
- `bootc switch --transport=TRANSPORT` accepts "registry, oci, oci-archive, docker-daemon, containers-storage"; the default is `registry`. `--enforce-container-sigpolicy` is the inverse of the old, now no-op, `--target-no-signature-verification` ([bootc-switch(8)](https://bootc.dev/bootc/man/bootc-switch.8.html)).
- bootc host storage is separate from podman storage, and the switched image is "queued for the next boot". The upstream example timer automates only `podman build`. Staging and reboot "are intentionally left as explicit operations" ([bootc local builds](https://bootc.dev/bootc/bootc-local-builds.7.html)).
- Offline/USB example: `skopeo copy docker://… oci:/path/myos.oci`, then `bootc switch --transport oci /var/mnt/usb/myos.oci` once, then `bootc upgrade --apply` ([bootc registries & offline](https://bootc.dev/bootc/bootc-registries-and-offline.7.html)).
- Insecure (HTTP) registries are configured with `insecure=true` in `/etc/containers/registries.conf.d`. bootc has no TLS-skip flag ([same page](https://bootc.dev/bootc/bootc-registries-and-offline.7.html)).
- Red Hat says that once local storage and the update source match, `bootc upgrade` works with no remote registry ([RHEL 10 offline updates](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/deploying-an-image-mode-update-in-offline-and-air-gapped-environments)). The containers-storage transport syntax was historically undocumented in the man page ([RHEL-40133](https://issues.redhat.com/browse/RHEL-40133)).

**Experimental unified storage**
- Steps: `bootc image copy-to-storage`, then `bootc switch --transport containers-storage localhost/bootc`, then `bootc image set-unified`, then `bootc image cmd build -t localhost/my-custom .`
- It is explicitly "not yet suitable for production use" ([unified storage](https://bootc.dev/bootc/bootc-experimental-unified-storage.7.html)).

**BlueBuild CLI**
- Commands: `bluebuild build ./recipes/recipe.yml` and `bluebuild switch ./recipes/recipe.yml [-r]` ([blue-build.org local](https://blue-build.org/how-to/local/)).
- `switch` builds an `oci-archive` tarball and moves it into `/etc/bluebuild` with sudo. The distrobox install is rootless and "can't be used to locally rebase" ([CLI README](https://raw.githubusercontent.com/blue-build/cli/main/README.md)).
- It works with Docker 23+, Podman 4+ or Buildah 1.29+ ([CLI README](https://raw.githubusercontent.com/blue-build/cli/main/README.md)).

**How uupd updates the system**
- uupd runs `bootc upgrade --check` (no update if the output contains "No changes in:"), then `bootc upgrade --quiet --progress-fd 3`.
- It flags the system as outdated if the booted image is more than one month old ([uupd system.go](https://raw.githubusercontent.com/ublue-os/uupd/main/drv/system/system.go)).
- Defaults: battery at least 20%, memory at most 90%. Overrides go in `/etc/uupd/config.json`. Images based on main may need rpm-ostreed's `AutomaticUpdatePolicy=stage` changed to avoid conflicts ([uupd README](https://github.com/ublue-os/uupd)).

**Community local auto-update pattern**
- A Universal Blue Discourse post (Feb 15–Mar 13, 2026) uses a Quadlet `.build` unit with `Pull=newer` and a daily timer. It runs `ExecStartPost=bootc switch --quiet --transport=containers-storage localhost/system-image:latest`, then `bootc update --quiet`, then `podman image prune --force --filter=label=containers.bootc=1`. It also disables uupd's system module.
- One user reported about 100 GB of accumulated images before adding pruning ([Discourse](https://universal-blue.discourse.group/t/locally-built-automatically-updating-custom-bootc-image/11706)).
- The same pattern is on Fedora Discussion (posted 2026-02-22, updated 2026-10-29), which also recommends `ostree admin pin 0` first ([Fedora Discussion](https://discussion.fedoraproject.org/t/fedora-atomic-a-simple-guide-to-creating-a-custom-local-bootc-image/181729)).

### Exact commands

**A. Build host is also the target (NVIDIA desktop)**
```bash
# Containerfile: FROM ghcr.io/ublue-os/bazzite-nvidia:stable
sudo just build bazzite-swayfx latest            # rootful -> /var/lib/containers/storage
sudo just ostree-rechunk bazzite-swayfx latest   # optional, privileged
sudo bootc switch --transport containers-storage localhost/bazzite-swayfx:latest
systemctl reboot
# Later updates: rebuild with the same tag, then
sudo bootc upgrade --apply    # or let uupd / a timer do it
```

**Rootless build variant**
```bash
podman build -t localhost/bazzite-swayfx:latest .
sudo podman image scp $UID@localhost::localhost/bazzite-swayfx:latest root@localhost::localhost/bazzite-swayfx:latest
```
(The second line follows the Justfile form.)

**B. Ship a file to the HTPC (`oci` dir or `oci-archive`)**
```bash
# On the builder:
sudo skopeo copy containers-storage:localhost/bazzite-bigscreen:latest oci:/var/tmp/bigscreen.oci
# or: sudo podman save --format oci-archive -o /var/tmp/bigscreen.tar localhost/bazzite-bigscreen:latest
#     (podman flag syntax not re-verified in this session)

# Copy to the HTPC (rsync/USB), then once:
sudo bootc switch --transport oci /var/lib/myos/bigscreen.oci
#   (or --transport oci-archive /var/lib/myos/bigscreen.tar)

# For each update: replace the file, then
sudo bootc upgrade --apply
```

**C. LAN registry (best for the HTPC)**
```bash
# On the builder: run a registry.
# The distribution image tag registry:2 is from memory; registry:3 also exists (UNVERIFIED).
sudo podman run -d --name registry -p 5000:5000 \
  -v /var/lib/registry:/var/lib/registry:Z docker.io/library/registry:2
sudo podman push --tls-verify=false localhost/bazzite-bigscreen:latest \
  192.168.1.10:5000/bazzite-bigscreen:latest
```
On each client, create `/etc/containers/registries.conf.d/50-lan.conf`:
```toml
[[registry]]
location = "192.168.1.10:5000"
insecure = true
```
Then switch once:
```bash
sudo bootc switch 192.168.1.10:5000/bazzite-bigscreen:latest
```
After that, `bootc upgrade` and uupd work exactly as they do with GHCR.

### Inferences
- **containers-storage:** `bootc upgrade` re-reads the same local tag. Rebuilding with the same tag and running upgrade (or uupd) stages the new build, and the Discourse and Fedora timer workflows rely on this. Nothing updates unless something rebuilds, and uupd's one-month "outdated" check will nag if builds stop.
- **oci / oci-archive:** updates happen only when you replace the file. BlueBuild `switch` works the same way through `/etc/bluebuild`, so automatic upgrades never see anything new until you run `bluebuild switch` again.
- **Signatures on local transports:** the stock ublue policy accepts containers-storage/oci/oci-archive with `insecureAcceptAnything` (see Q4). Local-transport deployments are effectively unsigned.
- **Disk and RAM (UNVERIFIED estimates, no primary benchmark found):**
  - The base is about 4.5–4.9 GB compressed, probably 10–15 GB unpacked.
  - Root podman storage (base + derived + rechunked copy) plus bootc's separate ostree copy plus the old deployment suggests budgeting 40–60 GB free and pruning regularly.
  - `ostree-rechunk` uses a tmpfs, so 16 GB+ RAM is advisable.
- **Build time:** I found no measurements. It is dominated by pulling about 5 GB (cached with `--pull=newer`), the dnf layers, and rechunking.

### Gaps
- No primary benchmark for build time, RAM or disk of a Bazzite-derived build.
- The Fedora "disconnected updates" page was blocked by Anubis bot protection, so I used the upstream bootc doc instead.
- Not verified: whether `bootc upgrade` on the `oci-archive` transport re-reads a replaced file in all bootc versions.

---

## Q2. Other CI systems

### Takeaway
GitLab.com Free can build these images, but the 400-minute monthly quota and the 30/50 GB runner disks make it tight. Codeberg's hosted CI is not usable for multi-GB OS images. A self-hosted runner (GitHub, GitLab or Forgejo) on your own box is the realistic non-GHA CI option.

### Cited findings
**GitLab.com**
- Free tier: 400 compute minutes per month. Cost factors are small 1, medium 2, large 3 (Linux x86-64). Public projects in the GitLab for Open Source program get 0.5, and their public forks 0.008. Other public projects pay the standard factor ([GitLab compute minutes](https://docs.gitlab.com/ci/pipelines/compute_minutes/)).
- Hosted runners on Free: `saas-linux-small-amd64` has 2 vCPU, 8 GB RAM, 30 GB disk; `medium` has 4 vCPU, 16 GB, 50 GB. Large and bigger are Premium/Ultimate only.
- Runners are privileged, so Docker-in-Docker works. The executor is `docker+machine` ([GitLab hosted Linux runners](https://docs.gitlab.com/ci/runners/hosted_runners/linux/)).
- BlueBuild's documented GitLab CI uses image `ghcr.io/blue-build/cli`, service `docker:dind`, and `COSIGN_PRIVATE_KEY` from GitLab Secure Files, running `bluebuild build --push ./recipes/$RECIPE` ([BlueBuild CLI README](https://raw.githubusercontent.com/blue-build/cli/main/README.md)). The blue-build.org GitLab how-to URL returned 404.
- Red Hat's GitLab image-mode pipeline (2026-02-12) builds with `registry.access.redhat.com/ubi10/podman` and pushes with `$CI_REGISTRY_*`. It runs bootc-image-builder for qcow2, and says the disk step needs privileged mode or a custom runner ([Red Hat Developer](https://developers.redhat.com/articles/2026/02/12/how-build-image-mode-pipeline-gitlab)).
- Other GitLab-based examples:
  - `gitlab.com/dunn.dev/immutable/basef`: bootc CI templates; the group is now archived ([issue](https://gitlab.com/dunn.dev/immutable/basef/-/issues/15)).
  - The Fedora IoT base-images `.gitlab-ci.yml` on forge.fedoraproject.org ([forge](https://forge.fedoraproject.org/iot/base-images)).
  - AlmaLinux [atomic-ci](https://github.com/AlmaLinux/atomic-ci), cited as having GitLab jobs; not verified.

**Codeberg**
- Hosted Forgejo Actions runners: `codeberg-tiny` (1 CPU/2G, 2 min), `codeberg-small` (2/4G, 5 min), `codeberg-medium` (4/8G, 10 min max runtime). Each gets 2 GB of extra temporary storage, and RAM use includes filesystem writes.
- Running a Docker daemon there is "not officially supported"; podman builds are "possible".
- Projects must be public and FLOSS-licensed. A 2026-10-19 commit added "No extensive pipelines to assist LLM-driven workflows" ([codeberg.org/actions/meta](https://codeberg.org/actions/meta)).
- Codeberg says hosted Actions are limited by "outstanding security issues and bus factor" and points people to Woodpecker ([Codeberg Actions docs](https://docs.codeberg.org/ci/actions/)).
- Woodpecker needs a manual application. Codeberg publishes no numeric limits ("resource usage must be reasonable") and recommends self-hosted agents for heavy work ([Codeberg CI](https://docs.codeberg.org/ci/)).
- Example: `codeberg.org/Universe_lord/School-Linux`, an image-template derivative with `.forgejo/workflows/build.yml` and `build-disk.yml` that pushes to Codeberg's registry. It was archived on 2026-06-17 ([repo](https://codeberg.org/Universe_lord/School-Linux)). `codeberg.org/cvsickle/bazzite-dx` is a GitHub mirror, not a native Forgejo build.

**GitHub self-hosted runners**
- The $0.002/min platform fee for self-hosted runners announced for March 2026 was postponed with no new date. Public-repo usage of standard hosted and self-hosted runners "remains free" ([GitHub pricing changes](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)).

### Inferences
- **Codeberg hosted runners:** 10 minutes and 2 GB of temp disk cannot even pull a 4.9 GB base image, so they are non-viable.
- **GitLab small runner:** 30 GB is likely too small for pull + build + rechunk + push. The medium runner (50 GB, factor 2) gives about 200 job-minutes a month, which is roughly 4–10 builds a month for two images, depending on build time (UNVERIFIED).

### Gaps
- No verified Woodpecker resource numbers for Codeberg.
- No maintained official BlueBuild GitLab template page found.
- Observed-content note: the dunn.dev GitLab issue page contains an embedded "AI Context" block telling AI readers to read repo files and use `glab`. I did not act on it.

---

## Q3. Other registries

### Takeaway
GitLab's registry, Quay (public), Docker Hub, zot, Harbor and distribution should all serve bootc images. Codeberg's package quota (1.5 GiB shared) is far below one Bazzite image. Private images need `/etc/ostree/auth.json` on clients.

### Cited findings
**GitLab Container Registry**
- On Free, the registry does not count toward the 10 GiB per-project limit, which covers only repo and LFS ([GitLab storage](https://docs.gitlab.com/user/storage_usage_quotas/)).
- Visibility follows the project: anonymous pulls only from public projects, or set it to "Only Project Members" ([GitLab registry](https://docs.gitlab.com/user/packages/container_registry/)).

**Docker Hub**
- Unauthenticated: 100 pulls per 6 hours per IPv4 or IPv6 /64. Personal: 200 per 6 hours. Pro/Team/Business: unlimited (fair use).
- "Using GET emulates a real pull and counts… Using HEAD won't" ([Docker Hub pulls](https://docs.docker.com/docker-hub/usage/pulls/)).
- Docker announced stricter limits in 2025 (UNVERIFIED from memory); the current page shows the figures above.

**Quay.io**
- Public repos are free; private repos need a paid plan ([Red Hat Quay docs](https://docs.redhat.com/en/documentation/red_hat_quay/3/html/about_quay_io/use-quay-create-repo)).
- Plan prices conflict between sources (e.g. Developer $15/mo per [Toolradar](https://toolradar.com/tools/quay/pricing)), so they are UNVERIFIED.
- quay.io/plans returned "Service is currently read-only" on 2026-11-22.

**Codeberg / Forgejo package registry**
- Codeberg defaults (2025-05-14): 750 MiB git, plus 1.5 GiB shared across LFS, packages, releases and attachments. Exceptions are by request ([Codeberg blog](https://blog.codeberg.org/new-storage-limits-on-codeberg-what-you-need-to-know.html)).
- Forgejo's registry "follows the OCI specifications" (docs v17.0). Nothing is documented about size limits or signatures ([Forgejo container docs](https://forgejo.org/docs/latest/user/packages/container/)).

**zot**
- Zot "fully conforms to the OCI Distribution Specification", supports cosign and notation, and does inline dedupe and garbage collection ([zot concepts](https://zotregistry.dev/v2.1.23/general/concepts/)).

**Client auth for private images**
- bootc reads `/run/ostree/auth.json`, `/etc/ostree/auth.json` or `/usr/lib/ostree/auth.json`. Podman's paths (e.g. `/root`) are not used.
- You can symlink with a tmpfiles.d entry such as `L /run/ostree/auth.json - - - - /var/lib/ostree/auth.json` ([bootc secrets](https://bootc.dev/bootc/building/bootc-secrets.7.html)).
- rpm-ostree also reads `/etc/ostree/auth.json` ([rpm-ostree container](https://coreos.github.io/rpm-ostree/container/)).

### Inferences
- **Layer counts:** 256 zstd layers already work on GHCR. Rechunking to 127–128 layers lowers the risk on stricter registries.
- **Docker Hub:** daily `bootc upgrade --check` from two machines is far below 100 per 6 hours, although manifest GETs probably count.

### Gaps
- No primary source for per-layer or per-image size caps on GitLab, Quay or Docker Hub.
- No source confirming zstd:chunked support specifically on Forgejo, Quay or Harbor.

---

## Q4. Signing and verification off GHCR

### Takeaway
Key-based cosign in the legacy tag format works on any registry that stores arbitrary tags and manifests. The ublue template already forces that format. Keyless (OIDC) signatures, e.g. from GitLab CI, currently do not verify in containers/image. Local transports cannot carry signatures.

### Cited findings
- The template signs with `cosign sign -y --new-bundle-format=false --use-signing-config=false --key env://COSIGN_PRIVATE_KEY IMG@DIGEST` using cosign v3.1.4. The comment says this lets it use cosign 3.x ([build.yml](https://raw.githubusercontent.com/ublue-os/image-template/main/.github/workflows/build.yml)).
- Cosign's new bundle format (the v3 default) always uses the OCI 1.1 referrers API, whereas legacy signatures use `sha256-<digest>.sig` tags ([sigstore OCI referrers](https://deploy-preview-411--docssigstore.netlify.app/cosign/container_registry/oci_referrers)).
- Cosign is tested against Docker Hub, distribution, GitLab, GHCR, Harbor and Quay. Zot and Forgejo are not listed ([sigstore registry support](https://docs.sigstore.dev/cosign/system_config/registry_support/)). Zot claims cosign support ([zot](https://zotregistry.dev/v2.1.23/general/concepts/)).
- GitLab displays cosign signatures (17.1+, cosign 2.0+) and supports the OCI 1.1 `subject` field, but "does not fully implement the OCI 1.1 Referrers API" ([GitLab registry](https://docs.gitlab.com/user/packages/container_registry/)).
- `sigstoreSigned` takes exactly one of `keyPath`, `keyPaths`, `keyData`, `keyDatas`, `fulcio` or `pki`. Registries need `use-sigstore-attachments` enabled in registries.d ([containers-policy.json(5)](https://raw.githubusercontent.com/containers/container-libs/main/image/docs/containers-policy.json.5.md)).
- The stock ublue `policy.json` has default `reject`, `ghcr.io/ublue-os` as `sigstoreSigned` with `keyPaths` ublue-os.pub and backup, and `matchRepository`. Every other docker scope, and all of containers-storage, oci, oci-archive and dir, are `insecureAcceptAnything` ([ublue-os-signing policy.json](https://raw.githubusercontent.com/ublue-os/packages/main/packages/ublue-os-signing/src/usr/etc/containers/policy.json)).
- `ostree-image-signed:docker://…` verifies against `/etc/containers/policy.json` ([rpm-ostree container](https://coreos.github.io/rpm-ostree/container/)). A missing registries.d `use-sigstore-attachments: true` entry gives "A signature was required, but no signature exists" ([Discourse](https://universal-blue.discourse.group/t/failed-to-invoke-method-openimage-a-signature-was-required-but-no-signature-exists/7335)).
- GitLab keyless OIDC certificates carry a SAN URI, which the containers/image `sigstoreSigned` matcher cannot match (it only does email). Upstream: container-libs#388, open since October 2025, status as of 2026-05-24 ([dunn.dev issue](https://gitlab.com/dunn.dev/immutable/basef/-/issues/15)).

### Client config for a self-hosted registry
In `policy.json`, under `transports.docker`:
```json
"192.168.1.10:5000/bazzite-bigscreen": [
  {"type": "sigstoreSigned",
   "keyPath": "/etc/pki/containers/mine.pub",
   "signedIdentity": {"type": "matchRepository"}}
]
```
In `/etc/containers/registries.d/mine.yaml`:
```yaml
docker:
  192.168.1.10:5000:
    use-sigstore-attachments: true
```
Bake both files into the image, then switch with:
```bash
bootc switch --enforce-container-sigpolicy 192.168.1.10:5000/bazzite-bigscreen:latest
```

### Inferences
- Unsigned LAN or GitLab images work out of the box because of the permissive default for other docker scopes. Signing there is optional hardening.
- Cosign against an HTTP registry needs its insecure-registry flag (name not verified for v3).

### Gaps
- Not verified: whether Forgejo's registry stores and serves cosign `.sig` tags correctly.

---

## Q5. GitHub Actions + GHCR baseline (brief)

### Cited findings
- The template workflow runs on a cron (`05 10 * * *`, daily), on push and PR, and on manual dispatch. It uses `runs-on: ubuntu-26.04` and the `ublue-os/remove-unwanted-software` action to free space. It then runs `just build`, `just ostree-rechunk`, `podman push` to GHCR, and cosign signing ([build.yml](https://raw.githubusercontent.com/ublue-os/image-template/main/.github/workflows/build.yml)).
- `build-disk.yml` builds ISO/qcow2 with bootc-image-builder, either as artifacts or uploaded to S3 ([README](https://github.com/ublue-os/image-template)).
- Standard runners: public repos get 4 vCPU, 16 GB RAM, 14 GB SSD; private repos get 2 vCPU, 8 GB RAM, 14 GB SSD ([GitHub runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).
- Public repos are free. Hosted prices dropped up to 39% on 2026-01-01. Free and Pro plans get "over 33 hours" of included compute for private repos ([GitHub pricing](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)).

### Inferences
- **Trade-offs:** the repo and image are public in practice (private repos burn minutes on half-size runners), you depend on GitHub, and the daily cron rebuilds whether or not the base changed.

---

## Comparison table

| Option | Cost (Nov 2026) | Setup effort | Build time / resources | Auto-updates on clients | Signing | ISO generation | Privacy | Main risks |
|---|---|---|---|---|---|---|---|---|
| GH Actions + GHCR | Free (public) | Low (template) | 4 vCPU/16 GB, 14 GB SSD + cleanup; no local load | Native (uupd / `bootc upgrade`) | Built-in cosign | `build-disk.yml` / Titanoboa | Public repo and image | GitHub lock-in, pricing/policy changes, disk squeeze |
| Local-only, containers-storage / oci-archive | $0 + power | Low (`sudo just build`) | Your CPU; ~40–60 GB disk, 16 GB RAM (UNVERIFIED) | Builder: via timer + `bootc upgrade`. Other box: only after manual file copy | None (local transports accept anything) | Local `just build-iso` (rootful, privileged) | Fully private | Manual copying, disk bloat, no signatures |
| Local build + LAN registry | $0 | Medium (registry + `insecure=true` conf) | Same as above + registry disk | Native on all clients while builder is on | Optional (cosign + policy.json) | Local bootc-image-builder | Private (LAN) | Builder downtime blocks updates; HTTP unless you add TLS |
| GitLab CI + registry | Free 400 min/mo; medium runner = 2x | Medium (BlueBuild `docker:dind` or custom) | 2–4 vCPU, 30/50 GB disk; tight | Native | Key-based cosign OK; keyless broken | Possible (privileged) | Private projects possible (needs auth.json) | Minute quota, disk limits |
| Forgejo / Codeberg | Free | High | Hosted runners: 10 min, 2 GB disk (non-viable) | Native if registry fits | Untested for Forgejo | Only with own runner | Public + FLOSS required on Codeberg | 1.5 GiB quota vs ~5 GB image; LLM-content ToS change |
| Self-hosted runner + any registry | Free on GH public (fee postponed) + hardware | Medium-high | Your hardware, no disk limits | Native | Yes | Yes | Depends on registry | Runner security and maintenance |

## Recommendation for one user with two machines

**Default: GitHub Actions + GHCR.** If public images are acceptable, it is the lowest-maintenance option: free, daily rebuilds, signing and ISOs built in, and clean uupd updates on both the NVIDIA desktop and the AMD HTPC. Use local `sudo just build` plus `bootc switch --transport containers-storage` only for fast iteration, then switch back to the GHCR tag.

**If you want privacy or no GitHub:** build both images on the NVIDIA desktop with a daily systemd timer. Push to a small LAN registry (distribution or zot) on that desktop. Configure both machines with `insecure=true` and point them at the LAN tags so uupd keeps working. Add cosign signing once it is stable.

**Avoid** Codeberg hosted CI and the oci-archive hand-copy workflow for day-to-day use.
