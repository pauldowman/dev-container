FROM rust:latest AS rust
FROM golang:latest AS golang
FROM ghcr.io/foundry-rs/foundry:latest AS foundry
FROM node:latest AS node

FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    git curl sudo zsh fzf ripgrep tmux \
    iproute2 dnsutils \
    openssh-client openssh-server jq vim gh gpg python3.12-venv \
    ca-certificates locales unzip \
    make m4 build-essential clang libclang-dev llvm-dev cmake direnv bat btop libatomic1 procps wget mold shellcheck \
    pkg-config libssl-dev libglib2.0-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
    libevent-2.1-7t64 libgstreamer-plugins-bad1.0-0 libflite1 libavif16 \
    libsqlite3-dev libpq-dev \
    libsnappy-dev liblz4-dev libzstd-dev libbz2-dev \
    protobuf-compiler libprotobuf-dev \
    libsasl2-dev \
    libudev-dev libdbus-1-dev \
    gcc-aarch64-linux-gnu gcc-x86-64-linux-gnu \
    zip \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y glow docker-ce-cli docker-compose-plugin docker-buildx-plugin google-cloud-cli \
    && apt-get clean

RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

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
    printf 'if [ -n "$SSH_AUTH_SOCK" ]; then\n    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"\n    tmux set-environment -g SSH_AUTH_SOCK "$SSH_AUTH_SOCK" 2>/dev/null || true\nfi\n' \
    > /home/$USERNAME/.ssh/rc && \
    chmod 755 /home/$USERNAME/.ssh/rc && \
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

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

USER $USERNAME

# Install dotfiles (optional)
RUN if [ -n "$DOTFILES_REPO" ]; then \
      git clone "$DOTFILES_REPO" ~/dotfiles && \
      cd ~/dotfiles && $DOTFILES_INSTALL_CMD; \
    fi

# Go language server
RUN go install golang.org/x/tools/gopls@latest

# Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Codex CLI and language servers (user-scope npm globals)
RUN npm config set prefix "$HOME/.npm-global" && \
    npm install -g typescript typescript-language-server @openai/codex@latest \
        pyright \
        @nomicfoundation/solidity-language-server \
        bash-language-server \
        tree-sitter-cli && \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' | sudo tee -a /etc/zsh/zshrc /etc/bash.bashrc > /dev/null

# Tuicr https://tuicr.dev/
RUN cargo install tuicr

# Custom user script (runs as user, after dotfiles and tools; optional)
RUN --mount=type=bind,source=.,target=/mnt/src \
    [ -f /mnt/src/custom-install-user.sh ] && bash /mnt/src/custom-install-user.sh || true

COPY scripts/start.sh /usr/local/bin/start.sh
CMD ["/usr/local/bin/start.sh"]
