# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ARG TARGETARCH
ARG MISE_VERSION=2026.7.5
ARG FNOX_VERSION=1.28.0
ARG PITCHFORK_VERSION=2.15.0
ARG CODEX_VERSION=0.144.1
ARG CODEX_INTEGRITY=sha512-Xir1zqPfpenhdoAoshN53uonzbBXj18COyzRkFlVZpSNyEl5XtkuYu9oddELePFN7K/0sXUcSO34Ad5IeCXPbw==
ARG SYMPHONY_COMMIT=4cbe3a9699a73b862466c0b157ceca0c1985d6d7

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_CACHE_DIR=/var/cache/mise \
    MISE_STATE_DIR=/var/lib/mise \
    FNOX_CONFIG_DIR=/etc/fnox \
    FNOX_NON_INTERACTIVE=true \
    PITCHFORK_STATE_DIR=/var/lib/pitchfork \
    SYMPHONY_WORKSPACE_ROOT=/workspaces/arrusted-development/.symphony/workspaces \
    MISE_TRUSTED_CONFIG_PATHS=/workspaces/arrusted-development \
    PATH=/opt/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        libncurses-dev \
        libssl-dev \
        openssh-client \
        pkg-config \
        socat \
        sudo \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && adduser --disabled-password --gecos "" --uid 1001 devbox \
    && echo "devbox ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/devbox \
    && chmod 0440 /etc/sudoers.d/devbox

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        mise_arch=x64; rust_arch=x86_64; \
        mise_sha=5f7ab76afdf0780d12edeaa67e908094e9ccf7924cfe203e415c1cfb87bbf778; \
        fnox_sha=64c0c7dcdf3194137f8f621fb33c65de59c37d8ad473c970dc18273ca039e2b0; \
        pitchfork_sha=a609adf7c4ce283e72c3512f522c0ef7cde59b0d22e75eccf5115764a0f715dd ;; \
      arm64) \
        mise_arch=arm64; rust_arch=aarch64; \
        mise_sha=41fcf744050bfa27f9871e2151ac6f44b5ce2741424b3d5282b92becc71e6bc4; \
        fnox_sha=8e465b3ec53cc244ec70e9d7f2a0de5495ed0410cef59c68ed9952e565b8f1ec; \
        pitchfork_sha=ccb6a2ef1bba97c6a1ecff845ed64f03bbc64ca77a33b4115df07d9f693d4364 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${mise_arch}" -o /usr/local/bin/mise; \
    echo "${mise_sha}  /usr/local/bin/mise" | sha256sum --check --strict; \
    chmod 0755 /usr/local/bin/mise; \
    curl -fsSL "https://github.com/jdx/fnox/releases/download/v${FNOX_VERSION}/fnox-${rust_arch}-unknown-linux-gnu.tar.gz" -o /tmp/fnox.tar.gz; \
    echo "${fnox_sha}  /tmp/fnox.tar.gz" | sha256sum --check --strict; \
    tar -xzf /tmp/fnox.tar.gz -C /usr/local/bin fnox; \
    curl -fsSL "https://github.com/jdx/pitchfork/releases/download/v${PITCHFORK_VERSION}/pitchfork-${rust_arch}-unknown-linux-gnu.tar.gz" -o /tmp/pitchfork.tar.gz; \
    echo "${pitchfork_sha}  /tmp/pitchfork.tar.gz" | sha256sum --check --strict; \
    tar -xzf /tmp/pitchfork.tar.gz -C /usr/local/bin pitchfork; \
    rm /tmp/fnox.tar.gz /tmp/pitchfork.tar.gz; \
    chmod 0755 /usr/local/bin/fnox /usr/local/bin/pitchfork

RUN mkdir -p /etc/mise /opt/mise /var/cache/mise /var/lib/mise \
    && mise install node@24.18.0 erlang@28.5 elixir@1.19.5-otp-28 \
    && mise use --global node@24.18.0 erlang@28.5 elixir@1.19.5-otp-28 \
    && cd /tmp \
    && codex_pack="$(mise exec node@24.18.0 -- npm pack "@openai/codex@${CODEX_VERSION}" --json)" \
    && echo "$codex_pack" | jq -e --arg expected "$CODEX_INTEGRITY" '.[0].integrity == $expected' >/dev/null \
    && codex_tarball="$(echo "$codex_pack" | jq -r '.[0].filename')" \
    && mise exec node@24.18.0 -- npm install --global "/tmp/${codex_tarball}" \
    && rm "/tmp/${codex_tarball}" \
    && mise reshim

RUN git clone https://github.com/openai/symphony.git /opt/symphony \
    && git -C /opt/symphony checkout --detach "$SYMPHONY_COMMIT" \
    && git -C /opt/symphony remote remove origin \
    && cd /opt/symphony/elixir \
    && mise trust \
    && MIX_ENV=prod mise exec -- mix local.hex --force \
    && MIX_ENV=prod mise exec -- mix local.rebar --force \
    && MIX_ENV=prod mise exec -- mix deps.get --only prod \
    && MIX_ENV=prod mise exec -- mix build \
    && test -x bin/symphony \
    && rm -rf /root/.cache /opt/symphony/.git

COPY config/fnox.toml /etc/fnox/config.toml
COPY config/pitchfork.toml /etc/pitchfork/config.toml
COPY bin/symphony /usr/local/bin/symphony
COPY bin/container-entrypoint /usr/local/bin/container-entrypoint
COPY bin/git-credential-github-token /usr/local/bin/git-credential-github-token

RUN chmod 0755 /usr/local/bin/symphony /usr/local/bin/container-entrypoint /usr/local/bin/git-credential-github-token \
    && mkdir -p /workspaces/arrusted-development /var/lib/pitchfork \
    && chown -R devbox:devbox \
        /workspaces \
        /var/lib/pitchfork \
        /opt/mise \
        /var/cache/mise \
        /var/lib/mise

WORKDIR /workspaces/arrusted-development
USER devbox

EXPOSE 4410

ENTRYPOINT ["/usr/local/bin/container-entrypoint"]
