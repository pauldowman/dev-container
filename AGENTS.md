# dev-container

> If anything in this repo confuses you, update this file before finishing so the next session doesn't repeat the same mistake.

A Docker-based development environment with SSH access, supporting multiple language toolchains.

## What it is

- Ubuntu base image with Go, Rust, Node.js, and Foundry (Ethereum) toolchains
- SSH-only access (no password auth) on port 2222 (localhost only)
- Code directory is volume-mounted at the same path inside and outside the container; host path (`CODE_DIR`) is passed into the container as `$CODE_DIR` for Docker socket compatibility
- Host Docker socket is mounted for running Docker commands inside the container
- Installs dotfiles from https://github.com/pauldowman/dotfiles
- Includes neovim, Claude CLI, tmux, zsh, fzf, ripgrep, fd (Ubuntu's `fd-find`, symlinked to `fd` in `/usr/local/bin`), mise, and dev tools
- Agent CLIs (claude, opencode, codex, omp) are installed user-scope (in the home volume) because they self-update in place; a root-owned system copy would break their updaters. Other npm globals are system-scope so rebuilds refresh them.

## Key files

- `Dockerfile` — multi-stage image build. The final/default `base` target is SSH-only; the opt-in `gui` target adds XFCE4 + xrdp. The xrdp/GUI login password is the username (`chpasswd`). The GUI stage wires `pam_gnome_keyring` into `/etc/pam.d/xrdp-sesman` so the GNOME login keyring is created/unlocked with that login password at login — without this, Secret Service apps (e.g. LibreSafe's vault pepper) hit a locked login keyring and prompt for a never-set password. The `home` volume persists keyrings; if a stale keyring with an unknown password is stuck, delete `~/.local/share/keyrings/*` and re-login so PAM recreates it.
- `docker-compose.yml` — runs the container; reads `USERNAME`, `SSH_AUTHORIZED_KEYS`, and `CODE_DIR` from env and tags each image by instance and build target
- `scripts/start.sh` — container entrypoint: writes SSH authorized_keys, sets up Docker socket access, starts sshd
- `scripts/docker-shim` — installed as `/usr/local/bin/docker` (shadows the real `/usr/bin/docker`). **macOS-host only:** on a Mac, the `/Users -> /home` symlink means path-canonicalizing tools (notably `cargo-prove --docker`) pass an unshared `/home/...` bind source that Docker Desktop rejects. The shim rewrites bind-mount sources to the shared host path, derived from `/proc/self/mountinfo`. No-op on Linux hosts (no Docker Desktop shared mounts).
- `scripts/ssh-agent-relink` — keeps `~/.ssh/agent.sock` (the stable agent path all shells use via `/etc/zsh/zshrc`) pointing at a live per-connection forwarded socket; only relinks when the current target is dead, so a newer connection closing doesn't strand older ones. Called from `scripts/ssh-rc` (installed as `~/.ssh/rc`) and a 60s watchdog loop in `scripts/start.sh`. Note `~/.ssh/rc` lives in the home volume, so image changes to it only reach fresh volumes — update the live file too.
- `custom-install-user.sh` — optional per-machine user setup, run as the user at **image build time** (`Dockerfile`). Anything it writes under `$HOME` lands in an image layer that the `home` volume shadows at runtime, and Docker seeds a named volume from the image only when that volume is created empty. So `./build` against an existing `home` volume does **not** re-apply those effects to the live home. Only the system-wide (`sudo`) installs here survive a rebuild. Build time also has no GitHub credentials — `dev` forwards `GH_TOKEN` per SSH session — so anything pulling from a private repo can't run here at all. Setup that needs credentials, or that has to re-apply on rebuild, belongs in a script run by hand inside the container instead. (Seeding `$HOME` at build time is still the right thing for anything a *fresh* volume should start with, e.g. the agent CLIs above.)
- `scripts/start-gui.sh` — GUI entrypoint: same as start.sh but also starts xrdp
- `build` — shell script that stops the selected container and rebuilds its image via Docker Compose; run `./start` afterward

## Build & run

```sh
# Rebuild and restart
./build
./start

# Build and start the opt-in GUI target after setting BUILD_TARGET=gui in .env
./build
./start
```

`./build` and `./start` validate `BUILD_TARGET`; supported values are `base` (the default) and `gui`. A configured legacy `DOCKERFILE` value is rejected so it cannot silently select an obsolete build path.

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
