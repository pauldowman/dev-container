FROM rust:latest AS rust
FROM golang:latest AS golang
FROM ghcr.io/foundry-rs/foundry:latest AS foundry
FROM node:latest AS node

FROM ubuntu:24.04 AS development

RUN apt-get update && apt-get install -y \
    git curl sudo zsh fzf ripgrep fd-find tmux \
    iproute2 dnsutils \
    openssh-client openssh-server jq vim gh gpg python3.12-venv \
    ca-certificates locales unzip \
    make m4 build-essential clang libclang-dev llvm-dev cmake direnv bat btop libatomic1 procps wget mold shellcheck \
    pkg-config libssl-dev libglib2.0-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
    libevent-2.1-7t64 libgstreamer-plugins-bad1.0-0 libflite1 libavif16 \
    libsqlite3-dev sqlite3 libpq-dev \
    libsnappy-dev liblz4-dev libzstd-dev libbz2-dev \
    protobuf-compiler libprotobuf-dev \
    libsasl2-dev \
    libudev-dev libdbus-1-dev \
    gcc-aarch64-linux-gnu gcc-x86-64-linux-gnu gcc-mips64-linux-gnuabi64 \
    zip \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update && apt-get install -y glow docker-ce-cli docker-compose-plugin docker-buildx-plugin google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && apt-get clean

RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# gcx (Grafana CLI) https://github.com/grafana/gcx
RUN curl -fsSL https://raw.githubusercontent.com/grafana/gcx/main/scripts/install.sh | INSTALL_DIR=/usr/local/bin sh

RUN ssh-keygen -A && \
    echo "PasswordAuthentication no\nAllowAgentForwarding yes\nAllowTcpForwarding yes" \
    > /etc/ssh/sshd_config.d/container.conf

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    COLORFGBG="15;0" \
    GTK_THEME=Adwaita:dark

# Copy Go
COPY --from=golang /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Copy Rust
COPY --from=rust /usr/local/rustup /usr/local/rustup
COPY --from=rust /usr/local/cargo /usr/local/cargo
ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo" \
    PATH="/usr/local/cargo/bin:${PATH}"

# Copy Node.js
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

# Copy Foundry binaries
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/
COPY --from=foundry /usr/local/bin/anvil /usr/local/bin/
COPY --from=foundry /usr/local/bin/chisel /usr/local/bin/

# mise (version manager)
RUN curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh && \
    echo 'eval "$(mise activate zsh)"' >> /etc/zsh/zshrc && \
    echo 'eval "$(mise activate bash)"' >> /etc/bash.bashrc && \
    echo 'export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"' >> /etc/zsh/zshrc

ARG USERNAME
ARG DOTFILES_REPO=""
ARG DOTFILES_INSTALL_CMD="./install.sh"

# Custom root script (runs as root, before user creation; optional)
RUN --mount=type=bind,source=.,target=/mnt/src \
    [ -f /mnt/src/custom-install-root.sh ] && bash /mnt/src/custom-install-root.sh || true

RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -ms /bin/zsh $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    ln -s /home /Users && \
    mkdir -p /home/$USERNAME/.ssh && \
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

# Stable SSH agent socket: ssh-agent-relink keeps ~/.ssh/agent.sock (the path
# all shells use via /etc/zsh/zshrc) pointing at a live per-connection
# forwarded socket, repairing the link when the connection it tracks closes.
# Called from ~/.ssh/rc on each connection and from a watchdog loop in start.sh.
COPY scripts/ssh-agent-relink /usr/local/bin/ssh-agent-relink
COPY --chown=$USERNAME:$USERNAME scripts/ssh-rc /home/$USERNAME/.ssh/rc

# Fix ownership of rust/cargo dirs for user and set default toolchain
RUN chown -R $USERNAME:$USERNAME /usr/local/rustup /usr/local/cargo
USER $USERNAME
RUN rustup default stable && \
    rustup component add rust-analyzer clippy rustfmt
# Symlink so rustup works even if RUSTUP_HOME isn't set in the shell (e.g. dotfiles override)
RUN ln -sf /usr/local/rustup ~/.rustup && ln -sf /usr/local/cargo ~/.cargo
USER root

# neovim
RUN ARCH=$(uname -m | sed 's/aarch64/arm64/') && \
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH}.tar.gz && \
    rm -rf /opt/nvim-linux-${ARCH} && \
    tar -C /opt -xzf nvim-linux-${ARCH}.tar.gz && \
    rm nvim-linux-${ARCH}.tar.gz && \
    ln -sf /opt/nvim-linux-${ARCH}/bin/nvim /usr/local/bin/nvim

# tmux-resurrect + tmux-continuum: auto-save/restore tmux sessions while their
# state remains in the container home. Loaded from /etc/tmux.conf (read before
# ~/.tmux.conf) so user dotfiles stay portable to other environments. Plugins
# live in /opt and are refreshed on rebuild; home state is ephemeral unless
# individual files are selected through data/home.
RUN git clone --depth 1 https://github.com/tmux-plugins/tmux-resurrect /opt/tmux-plugins/tmux-resurrect && \
    git clone --depth 1 https://github.com/tmux-plugins/tmux-continuum /opt/tmux-plugins/tmux-continuum && \
    printf '%s\n' \
      'set -g @continuum-restore "on"' \
      'run-shell /opt/tmux-plugins/tmux-resurrect/resurrect.tmux' \
      'run-shell /opt/tmux-plugins/tmux-continuum/continuum.tmux' \
      > /etc/tmux.conf

USER $USERNAME

# Default user config (overridden by dotfiles install below when DOTFILES_REPO is set)
COPY --chown=$USERNAME:$USERNAME defaults/ /home/$USERNAME/

# Install dotfiles (optional)
RUN if [ -n "$DOTFILES_REPO" ]; then \
      git clone "$DOTFILES_REPO" ~/dotfiles && \
      cd ~/dotfiles && $DOTFILES_INSTALL_CMD; \
    fi

# Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Language servers (system scope, refreshed on every rebuild)
USER root
RUN GOBIN=/usr/local/bin GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install golang.org/x/tools/gopls@latest && \
    rm -rf /tmp/gopath /tmp/gocache
RUN npm install -g typescript typescript-language-server \
        pyright \
        @nomicfoundation/solidity-language-server \
        bash-language-server \
        tree-sitter-cli
USER $USERNAME

# Codex CLI: user-scope (--prefix puts the binary in ~/.local/bin, already on
# PATH). Agent CLIs must be user-installed because they update themselves in
# place; root-owned system copies would break their updaters.
RUN npm install -g --prefix "$HOME/.local" @openai/codex@latest

# OpenCode CLI
RUN curl -fsSL https://opencode.ai/install | bash

# Oh My Pi (omp) coding agent — user-scope (self-updating, see note above)
RUN curl -fsSL https://omp.sh/install | sh

# Tuicr https://tuicr.dev/
RUN cargo install tuicr

# kubie
RUN cargo install kubie

# Custom user script (runs as user, after dotfiles and tools; optional)
RUN --mount=type=bind,source=.,target=/mnt/src \
    [ -f /mnt/src/custom-install-user.sh ] && bash /mnt/src/custom-install-user.sh || true

# docker shim (macOS-host only): on a Mac the /Users -> /home symlink makes
# path-canonicalizing tools like `cargo-prove --docker` pass an unshared /home/...
# bind source that Docker Desktop rejects; the shim rewrites it to the shared host
# path. No-op on Linux hosts. /usr/local/bin precedes /usr/bin on PATH, so this
# shadows the real docker (which it execs at /usr/bin/docker).
COPY scripts/docker-shim /usr/local/bin/docker

COPY scripts/link-home /usr/local/bin/link-home
COPY scripts/start.sh /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]

FROM development AS gui

ARG USERNAME
USER root

RUN echo "$USERNAME:$USERNAME" | chpasswd

RUN apt-get update && apt-get install -y xfce4 xrdp dbus-x11 fonts-liberation \
    gnome-keyring libsecret-tools \
    && adduser xrdp ssl-cert \
    && printf '#!/bin/sh\nexec startxfce4\n' > /etc/xrdp/startwm.sh \
    && apt-get clean \
    && rm -rf /usr/share/backgrounds/xfce/*

# Unlock the GNOME login keyring at xrdp login. Without this, apps that use the
# Secret Service (e.g. LibreSafe storing its vault pepper) hit a locked login
# keyring and prompt for a password that was never set. pam_gnome_keyring creates
# and unlocks the login keyring with the login password (the username, set by the
# chpasswd above), so it auto-unlocks every session with no prompt.
RUN printf 'auth     optional  pam_gnome_keyring.so\nsession  optional  pam_gnome_keyring.so auto_start\n' \
    >> /etc/pam.d/xrdp-sesman

COPY scripts/start-gui.sh /usr/local/bin/start-gui.sh

USER ${USERNAME}
RUN mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml && \
    printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<channel name="xsettings" version="1.0">\n\
  <property name="Net" type="empty">\n\
    <property name="ThemeName" type="string" value="Adwaita-dark"/>\n\
    <property name="IconThemeName" type="string" value="hicolor"/>\n\
  </property>\n\
</channel>\n' > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml && \
    printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<channel name="xfwm4" version="1.0">\n\
  <property name="general" type="empty">\n\
    <property name="workspace_count" type="int" value="1"/>\n\
    <property name="workspace_names" type="array">\n\
      <value type="string" value="Workspace 1"/>\n\
    </property>\n\
  </property>\n\
</channel>\n' > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

CMD ["/usr/local/bin/start-gui.sh"]

FROM development AS base-target-test
RUN ! command -v xrdp >/dev/null

FROM gui AS gui-target-test
RUN command -v xrdp >/dev/null

FROM development AS base
