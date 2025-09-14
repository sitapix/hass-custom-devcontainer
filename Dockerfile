ARG PYTHON_VERSION=3.13 # homeassistant==2025.3.4 requires Python>=3.13.0
FROM mcr.microsoft.com/devcontainers/python:1-${PYTHON_VERSION} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install system dependencies (grouped) and upgrade pip tooling.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bluez \
        libffi-dev \
        libssl-dev \
        libjpeg-dev \
        zlib1g-dev \
        autoconf \
        build-essential \
        libopenjp2-7 \
        libtiff6 \
        libturbojpeg0-dev \
        tzdata \
        ffmpeg \
        liblapack3 \
        liblapack-dev \
        libatlas-base-dev \
        git \
        libpcap-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    pip install --no-cache-dir --upgrade pip wheel setuptools; \
    pip install --no-cache-dir uv

COPY --from=ghcr.io/alexxit/go2rtc:latest /usr/local/bin/go2rtc /bin/go2rtc

EXPOSE 8123

VOLUME /config
RUN set -eux; \
    mkdir -p /config; \
    chown vscode:vscode /config

USER vscode
ENV VIRTUAL_ENV="/home/vscode/.local/ha-venv"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Create and populate virtual environment in one layer for caching.
# Create virtual environment (dependencies installed at runtime for flexibility / reduced build breakage)
RUN set -eux; \
    uv venv $VIRTUAL_ENV; \
    $VIRTUAL_ENV/bin/python -m ensurepip --upgrade; \
    $VIRTUAL_ENV/bin/python -m pip install --no-cache-dir --upgrade pip wheel setuptools; \
    echo 'Deferred Home Assistant installation to container start (see container script).'

COPY --chown=vscode:vscode container /usr/bin/container
COPY --chown=vscode:vscode hassfest /usr/bin/hassfest

ENTRYPOINT ["container"]