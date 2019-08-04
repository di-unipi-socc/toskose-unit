# toskose-unit - base image

ARG VERSION
ARG VCS_REF
ARG BUILD_DATE

ARG DEBIAN_VERSION=stretch
ARG PYTHON_VERSION=2.7.15

ARG SUPERVISORD_VERSION=3.3.5
ARG SUPERVISORD_REPOSITORY=https://github.com/Supervisor/supervisor/archive/${SUPERVISORD_VERSION}.tar.gz

# BASE IMAGE
FROM alpine as base

WORKDIR /tmp/scripts
COPY base/scripts/ .

RUN apk update --quiet \
    && apk add --no-cache --quiet \
    ca-certificates \
    && update-ca-certificates > /dev/null \
    && rm -rf /var/cache/apk/* \
    && chmod -R +x .

# FETCHER STAGE
# - check availabity of supervisord
# - fetch supervisord source code
# - manage the tarball
FROM base as fetcher

ARG SUPERVISORD_REPOSITORY
ARG SUPERVISORD_VERSION

WORKDIR /tmp/scripts
RUN mkdir -p /tmp/src/supervisord \
    && ./fetcher.sh ${SUPERVISORD_REPOSITORY} /tmp/src/supervisord \
    && ./archiver.sh /tmp/src/supervisord ${SUPERVISORD_VERSION}.tar.gz /tmp/src/supervisord \
    && rm /tmp/src/supervisord/${SUPERVISORD_VERSION}.tar.gz

### TESTING STAGE ###
FROM fetcher as source-tester

WORKDIR /tmp
RUN apk add --no-cache --quiet \
    tree \
    && tree -a \
    && apk del --quiet \
    tree \
    && rm -rf /var/cache/apk/*
### ------------- ###

# - Pyinstaller Issue with Alpine OS -
# (https://github.com/six8/pyinstaller-alpine)
# Alpine uses musl instead of glibc. The PyInstaller bootloader for Linux 64
# that comes with PyInstaller is made for glibc.
# This Docker image builds a bootloader with musl. (Not Working atm!)

# BUNDLER STAGE
# Bundling Supervisord (package freezing) into a standalone executable,
# including its dependencies (meld3) and the Python interpreter.
FROM python:${PYTHON_VERSION} as bundler

WORKDIR /supervisord
RUN mkdir -p src/ dist/ temp/

COPY --from=fetcher /tmp/src ./src/
COPY base/configs/pyinstaller/supervisord.spec /supervisord/supervisord.spec

# note: downgraded pip version (pip >=19 has issue with pyinstaller)
RUN python -m ensurepip \
    && pip install --quiet pip==18.1 \ 
    && pip install --quiet \
    setuptools \
    pyinstaller==3.4 \
    meld3 \
    && pyinstaller \
    --distpath /supervisord/dist \
    --workpath /supervisord/temp \
    --noconfirm \
    --clean \
    supervisord.spec

# RELEASE STAGE
# Supervisord with a minimal configuration
FROM debian:${DEBIAN_VERSION}-slim as release

ARG VERSION
ARG VCS_REF
ARG BUILD_DATE

LABEL org.label-schema.build-date=${BUILD_DATE} \
      org.label-schema.name="Toskose Unit" \
      org.label-schema.description="The base image used for the 'toskosing' process" \
      org.label-schema.vcs-url="https://github.com/di-unipi-socc/toskose-unit" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.vendor="SOCC Unipi" \
      org.label-schema.version=${VERSION} \
      org.label-schema.schema-version="1.0"

# https://github.com/docker/docker/issues/4032#issuecomment-34597177
ENV DEBIAN_FRONTEND=noninteractive

# entrypoint (includes also some initialization logic)
WORKDIR /toskose/supervisord
COPY base/entrypoint.sh .

RUN set -eu \
    && apt-get -qq update \
    && mkdir -p bundle/ config/ tmp/ logs/ \
    && touch logs/supervisord.log \
    && chmod +x entrypoint.sh \
    && apt-get -qq clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Supervisord Bundle (+ Python interpreter)
WORKDIR /toskose/supervisord/bundle
COPY --from=bundler /supervisord/dist/supervisord ./

# Supervisord config
WORKDIR /toskose/supervisord/config
COPY base/configs/supervisord/supervisord.conf .

# Create Apps structure (lifecycle scripts + logs)
# A test program is included
WORKDIR /toskose/apps/test
COPY base/apps/test/ .

RUN set -eu \
    && mkdir -p logs/ \
    && touch logs/test.log \
    && chmod -R 777 scripts/

# DEV ONLY
# !! overwrite ENVs in production !!
WORKDIR /toskose
ENV TOSCA_APP_NAME=toskose \
    SUPERVISORD_HTTP_PORT=9001 \
    SUPERVISORD_HTTP_USER=admin \
    SUPERVISORD_HTTP_PASSWORD=admin \
    SUPERVISORD_LOG_LEVEL=info

VOLUME /toskose/apps /toskose/supervisord/logs

ENTRYPOINT ["/bin/sh", "-c", "/toskose/supervisord/entrypoint.sh"]
