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
- Agent CLIs are installed user-scope in the image because they self-update in place during a container's lifetime; runtime updates disappear on recreation unless exact files are deliberately selected through `data/home`. Codex uses OpenAI's standalone installer, with `~/.local/bin/codex` targeting its user-writable package under `~/.codex/packages/standalone`; do not advertise `auth.json` as persistent without an authenticated rewrite test. Other npm globals remain system-scope under `/usr/local` so rebuilds refresh them.

## Key files

- `Dockerfile` — multi-stage image build. The final/default `base` target is SSH-only; the opt-in `gui` target adds XFCE4 + xrdp. The xrdp/GUI login password is the username (`chpasswd`). The GUI stage wires `pam_gnome_keyring` into `/etc/pam.d/xrdp-sesman` so the GNOME login keyring is created/unlocked with that login password at login. Keyring files are ephemeral unless exact files are selected under `data/home`; applications may atomically replace them, so persistence is not guaranteed without an application-specific test. If stale selected files cause an unknown-password prompt, remove their counterparts from `data/home/.local/share/keyrings` and re-login.
- `docker-compose.yml` — runs the container without a home volume; reads `USERNAME`, `SSH_AUTHORIZED_KEYS`, and `CODE_DIR` from env and tags each image by instance and build target
- `scripts/start.sh` — container entrypoint: creates the shared `data/home` source with runtime-user ownership, links its selected files into `$HOME`, writes runtime-managed SSH files, sets up Docker socket access, and starts sshd
- `scripts/docker-shim` — installed as `/usr/local/bin/docker` (shadows the real `/usr/bin/docker`). **macOS-host only:** on a Mac, the `/Users -> /home` symlink means path-canonicalizing tools (notably `cargo-prove --docker`) pass an unshared `/home/...` bind source that Docker Desktop rejects. The shim rewrites bind-mount sources to the shared host path, derived from `/proc/self/mountinfo`. No-op on Linux hosts (no Docker Desktop shared mounts).
- `scripts/ssh-agent-relink` — keeps `~/.ssh/agent.sock` (the stable agent path all shells use via `/etc/zsh/zshrc`) pointing at a live per-connection forwarded socket; only relinks when the current target is dead, so a newer connection closing doesn't strand older ones. Called from `scripts/ssh-rc` (installed as `~/.ssh/rc`) and a 60s watchdog loop in `scripts/start.sh`. The image supplies `~/.ssh/rc` again on each container recreation.
- `custom-install-user.sh` — optional per-machine user setup, run as the user at **image build time** (`Dockerfile`). Its writes under `$HOME` land in the image and appear in newly created containers. Build time has no GitHub credentials—`dev` forwards `GH_TOKEN` only for SSH sessions—so anything pulling from a private repository cannot run here. Setup needing credentials belongs in a script run by hand inside the container, where results are ephemeral unless exact files are selected through `data/home`.
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
- `CODE_DIR` — canonical absolute path to the code directory containing this repository (e.g. `/Users/paul/code`); symlink aliases are rejected because it is mounted at the same path inside the container and passed as `$CODE_DIR` for Docker-in-Docker volume paths

## Selective home persistence

The home directory is ephemeral across container recreation. The only persistence source is this repository's shared, gitignored `data/home`: each regular file or source symlink at `data/home/path` becomes a leaf symlink at `~/path` during startup, while directories only provide hierarchy and empty directories do nothing. All instances share these source files. Move an existing file to its exact `data/home` path and restart to opt it in. Because `CODE_DIR` is mounted at the same path, `data/home` is normally beneath `$HOME` inside the container (for example, `/home/paul/code/dev-container/data/home`); that nesting is intentional. The linker rejects identical roots, a destination root inside the source, and any selected relative path whose destination would map back into `data/home`.

Do not claim persistence for files an application updates by atomic rename because that can replace the destination symlink. Newly named files are not automatically selected. The linker rejects `.ssh/authorized_keys`, `.ssh/id_ed25519.pub`, `.ssh/agent.sock`, and descendants because startup manages them. Unlisted home state is discarded on recreation, while code persists through `CODE_DIR`. `data/` is outside the build context and ignored by Git, but `git clean -fdx` can still delete it.

When upgrading from the old named-home-volume configuration, selected files must be copied into `data/home` before the first rebuild when possible. The old `<instance>_home` volume is left orphaned rather than deleted and can be mounted read-only for recovery; `README.md` contains the exact procedure. A linker validation error stops startup before sshd, so recovery must be performed from the host by inspecting `docker logs <instance>` and fixing the offending `data/home` entry.

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
