# The base image is chosen per image in images.json and passed in by the
# Justfile (`just build <image>`), so the GPU base stays independent of the
# variant's package layer.
ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
# keys/ always exists (.gitkeep); it holds cosign.pub once signing is set up
COPY keys /keys

FROM ${BASE_IMAGE}

# Which build_files/variants/<variant>.sh and system_files/<variant>/ to apply
ARG VARIANT
# Optional add-ons, space-separated: build_files/features/<feature>.sh and
# system_files/features/<feature>/
ARG FEATURES=""
# Image identity, written into /usr/share/ublue-os/image-info.json
ARG IMAGE_NAME
ARG IMAGE_VENDOR=localhost

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
