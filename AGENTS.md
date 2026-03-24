# dev-container

> If anything in this repo confuses you, update this file before finishing so the next session doesn't repeat the same mistake.

A Docker-based development environment with SSH access, supporting multiple language toolchains.

## What it is

- Ubuntu base image with Go, Rust, Node.js, and Foundry (Ethereum) toolchains
- SSH-only access (no password auth) on port 2222 (localhost only)
- Code directory is volume-mounted at the same path inside and outside the container (for Docker socket compatibility)
- Host Docker socket is mounted for running Docker commands inside the container
- Installs dotfiles from https://github.com/pauldowman/dotfiles
- Includes neovim, Claude CLI, tmux, zsh, fzf, ripgrep, mise, and dev tools

## Key files

- `Dockerfile` — main image build
- `Dockerfile.gui` — extends main image with XFCE4 + xrdp for GUI access
- `docker-compose.yml` — runs the container; reads `USERNAME`, `SSH_AUTHORIZED_KEYS`, and `CODE_DIR` from env
- `scripts/start.sh` — container entrypoint: writes SSH authorized_keys, sets up Docker socket access, starts sshd
- `scripts/start-gui.sh` — GUI entrypoint: same as start.sh but also starts xrdp
- `build` — shell script to rebuild and restart the container via docker compose

## Build & run

```sh
# Rebuild and restart
./build

# With a specific Dockerfile (e.g. GUI variant)
DOCKERFILE=Dockerfile.gui ./build
```

Required env vars (typically in `.env`):
- `USERNAME` — the container user (should match host username)
- `SSH_AUTHORIZED_KEYS` — newline-separated public keys; first key is also used as the user's public key
- `CODE_DIR` — absolute path to code directory (e.g. `/Users/paul/code`), mounted at the same path inside and outside the container for Docker socket compatibility

## Connecting

Use the `dev` script to connect. It opens (or reattaches to) a named tmux session in `~/code/<session-name>` and forwards the GitHub token:

```sh
./dev <session-name>   # e.g. ./dev my-project
./dev list             # list active tmux sessions
```

The script connects to `localhost:2222` by default. If `REMOTE_DEV_SERVER` is set in `.env`, it uses that host as a jump host and reports the remote hostname when connecting.

Optional `.env` vars:
- `SSH_USERNAME` — override the SSH username (defaults to `$USER`)
- `REMOTE_DEV_SERVER` — if set, used as a jump host (`-J`) to reach the container on a remote machine
- `FORWARD_PORTS` — comma-separated list of ports to forward locally

Run `eval "$(./dev --init)"` to enable zsh tab completion for session names and `~/code` subdirectories.
