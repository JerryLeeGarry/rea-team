# Clean-room image for the Rebuilder.
# Firewall packages, non-root user, and sudo limited to init-firewall.sh follow
# the Claude Code reference devcontainer (anthropics/claude-code .devcontainer).
# Node is 22, within the REA floor of 22.19+ / 24.11+ / 26+.
FROM node:22-bookworm

ARG TZ=UTC
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG ALLOW_NPM=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    aggregate \
    bind9-dnsutils \
    ca-certificates \
    curl \
    dnsutils \
    git \
    iproute2 \
    ipset \
    iptables \
    jq \
    less \
    nano \
    procps \
    sudo \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN node -e 'const p=process.versions.node.split(".").map(Number); const ok=(p[0]===22&&p[1]>=19)||(p[0]===24&&p[1]>=11)||p[0]>=26; if(!ok){console.error("Node "+process.versions.node+" is below 22.19 / 24.11 / 26"); process.exit(1)}'

RUN mkdir -p /usr/local/share/npm-global /home/node/.claude /work /etc/rea-clean \
  && chown -R node:node /usr/local/share/npm-global /home/node/.claude /work

# Root-owned flag. The Rebuilder (user node) cannot flip this back to 1.
# Rebuild with --build-arg ALLOW_NPM=0 after dependency install.
RUN case "$ALLOW_NPM" in \
      0|1) printf '%s\n' "$ALLOW_NPM" > /etc/rea-clean/allow-npm ;; \
      *) echo "ALLOW_NPM must be 0 or 1" >&2; exit 1 ;; \
    esac \
  && chmod 444 /etc/rea-clean/allow-npm

COPY init-firewall.sh rea-entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/init-firewall.sh /usr/local/bin/rea-entrypoint.sh \
  && echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall \
  && chmod 0440 /etc/sudoers.d/node-firewall \
  && visudo -cf /etc/sudoers.d/node-firewall

USER node
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH="/usr/local/share/npm-global/bin:${PATH}"
ENV SHELL=/bin/bash
ENV EDITOR=nano
ENV VISUAL=nano
ENV CLAUDE_CONFIG_DIR=/home/node/.claude
ENV DEVCONTAINER=true

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/rea-entrypoint.sh"]
CMD ["sleep", "infinity"]
