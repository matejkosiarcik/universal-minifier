#
# checkov:skip=CKV_DOCKER_2:Disable HEALTHCHECK
# ^^^ Healhcheck doesn't make sense, because we are building a CLI tool, not server program
# checkov:skip=CKV_DOCKER_7:Disable FROM :latest
# ^^^ false positive for `--platform=$BUILDPLATFORM`

# hadolint global ignore=DL3042
# ^^^ Allow pip's cache, because we use it for cache mount

# NodeJS/NPM #
FROM --platform=$BUILDPLATFORM node:21.1.0-slim AS minifiers-nodejs-build
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends moreutils >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY minifiers/package.json minifiers/package-lock.json ./
RUN NODE_OPTIONS=--dns-result-order=ipv4first npm ci --unsafe-perm --no-progress --no-audit --quiet && \
    npx modclean --patterns default:safe --run --error-halt
    # Can't run `node-prune`, because it removes files which are used at runtime
COPY minifiers/tsconfig.json ./
COPY minifiers/js/src/ ./js/src/
RUN npm run build && \
    npm prune --production
COPY docker-utils/prune-dependencies/prune-nodejs.sh docker-utils/prune-dependencies/.common.sh /utils/
RUN sh /utils/prune-nodejs.sh

FROM debian:12.2-slim AS minifiers-nodejs-final
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends nodejs npm >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY docker-utils/sanity-checks/check-minifiers-nodejs.sh ./check-minifiers-nodejs.sh
COPY --from=minifiers-nodejs-build /app/node_modules ./node_modules/
COPY --from=minifiers-nodejs-build /app/package.json ./package.json
COPY --from=minifiers-nodejs-build /app/js/dist ./js/dist/
ENV YAML_MINIFIER=/app/js/dist/yaml.js
RUN sh check-minifiers-nodejs.sh

### Helpers ###

# Main CLI #
FROM --platform=$BUILDPLATFORM node:21.1.0-slim AS cli-build
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends moreutils >/dev/null && \
    rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN NODE_OPTIONS=--dns-result-order=ipv4first npm ci --unsafe-perm --no-progress --no-audit --quiet && \
    npx modclean --patterns default:safe --run --error-halt && \
    npx node-prune
COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build && \
    npm prune --production
COPY docker-utils/prune-dependencies/prune-nodejs.sh docker-utils/prune-dependencies/.common.sh /utils/
RUN sh /utils/prune-nodejs.sh

FROM debian:12.2-slim AS cli-final
WORKDIR /app
COPY --from=cli-build /app/dist ./dist
COPY --from=cli-build /app/node_modules ./node_modules
COPY --from=cli-build /app/package.json ./package.json

# Pre-Final #
FROM debian:12.2-slim AS pre-final
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        nodejs npm \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/* && \
    printf '%s\n%s\n%s\n' '#!/bin/sh' 'set -euf' 'node /app/dist/cli.js $@' >usr/bin/uniminify && \
    chmod a+x usr/bin/uniminify
COPY docker-utils/sanity-checks/check-system.sh ./
RUN sh check-system.sh
WORKDIR /app
COPY VERSION.txt ./
COPY --from=cli-final /app/ ./
WORKDIR /app/minifiers
COPY --from=minifiers-nodejs-final /app/ ./
WORKDIR /utils

### Final stage ###

FROM debian:12.2-slim
WORKDIR /app
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_TERSE=yes DEBCONF_NOWARNINGS=yes apt-get install -qq --yes --no-install-recommends \
        nodejs npm \
        >/dev/null && \
    rm -rf /var/lib/apt/lists/* /var/log/apt /var/log/dpkg* /var/cache/apt /usr/share/zsh/vendor-completions && \
    useradd --create-home --no-log-init --shell /bin/sh --user-group --system uniminify
COPY --from=pre-final /usr/bin/uniminify /usr/bin/
COPY --from=pre-final /app/ ./
ENV NODE_OPTIONS=--dns-result-order=ipv4first
USER uniminify
WORKDIR /project
ENTRYPOINT ["uniminify"]
CMD []