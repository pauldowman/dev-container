FROM rust:1.83 AS rust
FROM golang:1.23 AS golang
FROM ghcr.io/foundry-rs/foundry:latest AS foundry
FROM node:22-bookworm AS node

FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    git curl sudo zsh fzf ripgrep tmux \
    iproute2 dnsutils \
    openssh-client jq vim gh gpg python3.12-venv \
    ca-certificates locales \
    && locale-gen en_US.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

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
    bash-language-server

# Install rust-analyzer
RUN rustup component add rust-analyzer clippy

ARG USERNAME
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -ms /bin/zsh $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /workspace/code && chown -R $USERNAME /workspace

# Fix ownership of rust/cargo dirs for user
RUN chown -R $USERNAME:$USERNAME /usr/local/rustup /usr/local/cargo

WORKDIR /workspace

USER $USERNAME

# Install dotfiles
RUN git clone https://github.com/pauldowman/dotfiles.git ~/dotfiles && \
    cd ~/dotfiles && ./install.sh

# Go language server
RUN go install golang.org/x/tools/gopls@latest

# Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash
