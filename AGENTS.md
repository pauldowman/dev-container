# dev-container

> If anything in this repo confuses you, update this file before finishing so the next session doesn't repeat the same mistake.

A Docker-based development environment with SSH access, supporting multiple language toolchains.

## What it is

- Ubuntu base image with Go, Rust, Node.js, and Foundry (Ethereum) toolchains
- SSH-only access (no password auth) on port 2222 (localhost only)
- Code directory is volume-mounted at the same path inside and outside the container; host path (`CODE_DIR`) is passed into the container as `$CODE_DIR` for Docker socket compatibility
- Host Docker socket is mounted for running Docker commands inside the container
- Installs dotfiles from https://github.com/pauldowman/dotfiles
- Includes neovim, Claude CLI, tmux, zsh, fzf, ripgrep, mise, and dev tools

## Key files

- `Dockerfile` — main image build
- `Dockerfile.gui` — extends main image with XFCE4 + xrdp for GUI access
- `docker-compose.yml` — runs the container; reads `USERNAME`, `SSH_AUTHORIZED_KEYS`, and `CODE_DIR` from env
- `scripts/start.sh` — container entrypoint: writes SSH authorized_keys, sets up Docker socket access, starts sshd
- `scripts/docker-shim` — installed as `/usr/local/bin/docker` (shadows the real `/usr/bin/docker`). **macOS-host only:** on a Mac, the `/Users -> /home` symlink means path-canonicalizing tools (notably `cargo-prove --docker`) pass an unshared `/home/...` bind source that Docker Desktop rejects. The shim rewrites bind-mount sources to the shared host path, derived from `/proc/self/mountinfo`. No-op on Linux hosts (no Docker Desktop shared mounts).
- `scripts/start-gui.sh` — GUI entrypoint: same as start.sh but also starts xrdp
- `build` — shell script to rebuild and restart the container via docker compose

## Build & run

```sh
# Rebuild and restart
./build

# With a specific Dockerfile (e.g. GUI variant)
DOCKERFILE=Dockerfile.gui ./build
```

Required env vars (typically in `.env`, with per-instance overrides in `.env.<instance>`):
- `USERNAME` — the container user (should match host username)
- `SSH_AUTHORIZED_KEYS` — newline-separated public keys; first key is also used as the user's public key
- `CODE_DIR` — absolute path to code directory (e.g. `/Users/paul/code`), mounted at the same path inside the container; passed as `$CODE_DIR` so Docker-in-Docker volume paths work

## Connecting

Use the `dev` script to connect. It opens (or reattaches to) a named tmux session in `~/code/<session-name>` and forwards the GitHub token:

```sh
./dev <session-name>   # e.g. ./dev my-project
./dev list             # list active tmux sessions
```

The script connects to `localhost:2222`. To connect from a remote machine, SSH to the host and run the script there:

```sh
ssh -t dev /home/paul/code/dev-container/dev <session-name>
```

Port forwarding from the container is handled via `LocalForward` entries in the remote machine's `~/.ssh/config` for the host.

Run `eval "$(./dev --init)"` to enable zsh tab completion for session names and `~/code` subdirectories.
