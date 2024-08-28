# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG

ARG GO_IMAGE_NAME
ARG GO_IMAGE_TAG
FROM ${GO_IMAGE_NAME}:${GO_IMAGE_TAG} AS builder

ARG UNPOLLER_VERSION

SHELL ["/bin/bash", "-c"]

COPY scripts/start-unpoller.sh /scripts/
COPY patches /patches

RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install git patch \
    && mkdir -p /root/unpoller-build \
    # Download unpoller repo. \
    && git clone --quiet --depth 1 --branch ${UNPOLLER_VERSION:?} https://github.com/unpoller/unpoller /root/unpoller-build

WORKDIR /root/unpoller-build

# hadolint ignore=DL4006,SC2035
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Apply the patches. \
    && (find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p2 -i) \
    # Build Unpoller. \
    && go mod tidy \
    && CGO_ENABLED=0 GOOS=linux go build -a . \
    # Copy the build artifacts. \
    && mkdir -p /output/bin /output/scripts /output/configs \
    && cp /scripts/start-unpoller.sh /output/scripts/ \
    && cp unpoller /output/bin/ \
    && cp examples/up.conf.example /output/configs/unpoller.conf

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG UNPOLLER_VERSION

# hadolint ignore=DL4006,SC2086
RUN --mount=type=bind,target=/unpoller-build,from=builder,source=/output \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/unpoller-${UNPOLLER_VERSION:?}/bin /data/unpoller/{config,web} \
    && cp /unpoller-build/bin/unpoller /opt/unpoller-${UNPOLLER_VERSION:?}/bin \
    && cp /unpoller-build/configs/unpoller.conf /data/unpoller/config/unpoller.conf \
    && ln -sf /opt/unpoller-${UNPOLLER_VERSION:?} /opt/unpoller \
    && ln -sf /opt/unpoller/bin/unpoller /opt/bin/unpoller \
    # Copy the start-unpoller.sh script. \
    && cp /unpoller-build/scripts/start-unpoller.sh /opt/unpoller/ \
    && ln -sf /opt/unpoller/start-unpoller.sh /opt/bin/start-unpoller \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /opt/unpoller-${UNPOLLER_VERSION:?} /opt/unpoller /opt/bin/{unpoller,start-unpoller} /data/unpoller \
    # Clean up. \
    && homelab cleanup

# Expose the prometheus metrics exporter port.
EXPOSE 9130
# Expose the web API port.
EXPOSE 37288

# Use the healthcheck command part of unpoller as the health checker.
HEALTHCHECK \
    --start-period=15s --interval=30s --timeout=3s \
    CMD curl \
        --silent \
        --fail \
        --location \
        --show-error \
        --insecure \
        https://localhost:37288/health

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-unpoller"]
STOPSIGNAL SIGTERM
