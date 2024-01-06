#
# checkov:skip=CKV_DOCKER_2:Disable HEALTHCHECK
# ^^^ Healhcheck doesn't make sense, because we are building a CLI tool, not server program
# checkov:skip=CKV_DOCKER_7:Disable FROM :latest
# ^^^ false positive for `--platform=$BUILDPLATFORM`

# hadolint global ignore=DL3042
# ^^^ Allow pip's cache, because we use it for cache mount

### Main CLI ###

FROM --platform=$BUILDPLATFORM node:21.5.0-slim AS cli-build
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        moreutils \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY cli/package.json cli/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    NODE_OPTIONS=--dns-result-order=ipv4first npm ci --unsafe-perm --no-progress --no-audit --quiet && \
    chronic npx modclean --patterns default:safe --run --error-halt --no-progress
COPY cli/tsconfig.json ./
COPY cli/rollup.config.js ./
COPY cli/src/ ./src/
RUN npm run --silent build && \
    npm prune --production --silent --no-progress --no-audit
COPY docker-utils/prune-dependencies/prune-npm.sh docker-utils/prune-dependencies/.common.sh /utils/
RUN sh /utils/prune-npm.sh

FROM debian:12.4-slim AS cli-final
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        moreutils nodejs npm \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY --from=cli-build /app/node_modules ./node_modules
COPY --from=cli-build /app/package.json ./package.json
COPY --from=cli-build /app/dist/ ./dist/
COPY docker-utils/sanity-checks/check-minifiers-custom.sh /utils/check-minifiers-custom.sh
RUN chronic sh /utils/check-minifiers-custom.sh

### Reusable components ###

# Gitman #
FROM --platform=$BUILDPLATFORM debian:12.4-slim AS gitman-reusable
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        python3 python3-pip git >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY docker-utils/dependencies/gitman/requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --requirement requirements.txt --target python --quiet
ENV PATH="/app/python/bin:$PATH" \
    PYTHONPATH=/app/python

### 3rd party minifiers ###

# Bash-minifier #
FROM --platform=$BUILDPLATFORM gitman-reusable AS minifiers-bash-build
COPY minifiers/gitman/bash-minifier/gitman.yml ./
RUN --mount=type=cache,target=/root/.gitcache \
    gitman install --quiet

FROM --platform=$BUILDPLATFORM debian:12.4-slim AS minifiers-bash-final
WORKDIR /app
COPY --from=bash-minifier-build1 /app/gitman/bash-minifier ./bash-minifier/

# NodeJS/NPM #

FROM --platform=$BUILDPLATFORM node:21.5.0-slim AS minifiers-nodejs-build1
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        moreutils \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY minifiers/package.json minifiers/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    NODE_OPTIONS=--dns-result-order=ipv4first npm ci --unsafe-perm --no-progress --no-audit --quiet && \
    chronic npx modclean --patterns default:safe --run --error-halt --no-progress && \
    npm prune --production --silent --no-progress --no-audit

FROM --platform=$BUILDPLATFORM debian:12.4-slim AS minifiers-nodejs-build2
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        moreutils nodejs inotify-tools psmisc \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY --from=minifiers-nodejs-build1 /app/node_modules/ ./node_modules/
COPY --from=minifiers-nodejs-build1 /app/package.json ./package.json
COPY docker-utils/sanity-checks/check-minifiers-nodejs.sh /utils/
ENV PATH="/app/node_modules/.bin:$PATH"
RUN touch /usage-list.txt && \
    inotifywait --daemon --recursive --event access /app/node_modules --outfile /usage-list.txt --format '%w%f' && \
    chronic sh /utils/check-minifiers-nodejs.sh && \
    killall inotifywait
COPY docker-utils/prune-dependencies/prune-inotifylist.sh /utils/prune-inotifylist.sh
RUN sh /utils/prune-inotifylist.sh ./node_modules /usage-list.txt

FROM debian:12.4-slim AS minifiers-nodejs-final
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        moreutils nodejs \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY --from=minifiers-nodejs-build2 /app/node_modules ./node_modules/
COPY --from=minifiers-nodejs-build2 /app/package.json ./package.json
COPY docker-utils/sanity-checks/check-minifiers-nodejs.sh /utils/
ENV PATH="/app/node_modules/.bin:$PATH"
RUN chronic sh /utils/check-minifiers-nodejs.sh

# Python #

FROM --platform=$BUILDPLATFORM debian:12.4-slim AS minifiers-python-build1
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        jq moreutils python3 python3-pip \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY minifiers/requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --requirement requirements.txt --target "$PWD/python" --quiet && \
    find /app/python -type f -iname '*.py[co]' -delete && \
    find /app/python -type d -iname '__pycache__' -prune -exec rm -rf {} \;

FROM --platform=$BUILDPLATFORM debian:12.4-slim AS minifiers-python-build2
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        jq moreutils python3 inotify-tools psmisc \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY --from=minifiers-python-build1 /app/python/ ./python/
COPY docker-utils/sanity-checks/check-minifiers-python.sh /utils/
ENV PATH="/app/python/bin:$PATH" \
    PYTHONPATH=/app/python \
    PYTHONDONTWRITEBYTECODE=1
RUN touch /usage-list.txt && \
    inotifywait --daemon --recursive --event access /app/python --outfile /usage-list.txt --format '%w%f' && \
    chronic sh /utils/check-minifiers-python.sh && \
    killall inotifywait
COPY docker-utils/prune-dependencies/prune-inotifylist.sh /utils/prune-inotifylist.sh
RUN sh /utils/prune-inotifylist.sh ./python /usage-list.txt

FROM debian:12.4-slim AS minifiers-python-final
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        jq moreutils python3 \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY --from=minifiers-python-build2 /app/python ./python/
COPY docker-utils/sanity-checks/check-minifiers-python.sh /utils/
ENV PATH="/app/python/bin:$PATH" \
    PYTHONPATH=/app/python \
    PYTHONDONTWRITEBYTECODE=1
RUN chronic sh /utils/check-minifiers-python.sh

# Pre-Final #
# The purpose of this stage is to be 99% the same as the final stage
# Mainly the apt install scripts should be the same
# But since it's not actually final we can run some sanity-checks, which fo not baloon the size of the output docker image

FROM debian:12.4-slim AS pre-final
RUN find / -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/*.txt' >/before.txt 2>/dev/null && \
    apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        jq moreutils nodejs python3 \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/* && \
    find /usr/share/bug /var/cache /var/lib/apt /var/log -type f | while read -r file; do \
        if ! grep -- "$file" </before.txt >/dev/null; then rm -f "$file"; fi \
    done && \
    rm -f /before.txt && \
    printf '%s\n%s\n%s\n' '#!/bin/sh' 'set -euf' 'node /app/dist/cli.js $@' >/usr/bin/uniminify && \
    chmod a+x /usr/bin/uniminify
COPY docker-utils/sanity-checks/check-system.sh /utils/
RUN chronic sh /utils/check-system.sh
WORKDIR /app
COPY VERSION.txt ./
COPY --from=cli-final /app/ ./
WORKDIR /app/minifiers
COPY --from=minifiers-nodejs-final /app/ ./
COPY --from=minifiers-python-final /app/ ./

### Final stage ###

FROM debian:12.4-slim
RUN find / -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/*.txt' >/before.txt 2>/dev/null && \
    apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        jq nodejs python3 \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/* && \
    find /usr/share/bug /var/cache /var/lib/apt /var/log -type f | while read -r file; do \
        if ! grep -- "$file" </before.txt >/dev/null; then rm -f "$file"; fi \
    done && \
    rm -f /before.txt && \
    printf '%s\n%s\n%s\n' '#!/bin/sh' 'set -euf' 'node /app/dist/cli.js $@' >/usr/bin/uniminify && \
    chmod a+x /usr/bin/uniminify && \
    useradd --create-home --no-log-init --shell /bin/sh --user-group --system uniminify
COPY --from=pre-final /app/ /app/
ENV NODE_OPTIONS=--dns-result-order=ipv4first \
    PYTHONDONTWRITEBYTECODE=1
USER uniminify
WORKDIR /project
ENTRYPOINT ["uniminify"]
CMD []
