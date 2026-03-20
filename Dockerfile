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
    just make build-essential clang direnv bat btop libatomic1 procps wget mold \
    pkg-config libssl-dev libglib2.0-dev libgtk-3-dev libwebkit2gtk-4.1-dev \
    && locale-gen en_US.UTF-8 \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list \
    && apt-get update && apt-get install -y glow \
    && apt-get clean

RUN ssh-keygen -A && \
    echo "PasswordAuthentication no\nAllowAgentForwarding yes\nAllowTcpForwarding yes" \
    > /etc/ssh/sshd_config.d/container.conf

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

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

# Install global npm packages (now that node is available)
RUN npm install -g typescript typescript-language-server @openai/codex@latest \
    pyright \
    @nomicfoundation/solidity-language-server \
    bash-language-server \
    tree-sitter-cli

# Install rust-analyzer
RUN rustup component add rust-analyzer clippy

ARG USERNAME
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -ms /bin/zsh $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Fix ownership of rust/cargo dirs for user
RUN chown -R $USERNAME:$USERNAME /usr/local/rustup /usr/local/cargo

# neovim
RUN ARCH=$(uname -m | sed 's/aarch64/arm64/') && \
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH}.tar.gz && \
    rm -rf /opt/nvim-linux-${ARCH} && \
    tar -C /opt -xzf nvim-linux-${ARCH}.tar.gz && \
    rm nvim-linux-${ARCH}.tar.gz && \
    ln -sf /opt/nvim-linux-${ARCH}/bin/nvim /usr/local/bin/nvim

USER $USERNAME

# Install dotfiles
RUN git clone https://github.com/pauldowman/dotfiles.git ~/dotfiles && \
    cd ~/dotfiles && ./install.sh

# Go language server
RUN go install golang.org/x/tools/gopls@latest

# Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN /home/paul/.local/bin/claude plugin marketplace add austintgriffith/ethskills && \
    /home/paul/.local/bin/claude plugin install ethskills

# Tuicr https://tuicr.dev/
RUN cargo install tuicr

# mise
RUN curl https://mise.run | sh && \
    echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc.local

