# dev-container

> If anything in this repo confuses you, update this file before finishing so the next session doesn't repeat the same mistake.

A Docker-based development environment with SSH access, supporting multiple language toolchains.

## What it is

- Ubuntu base image with Go, Rust, Node.js, and Foundry (Ethereum) toolchains
- SSH-only access (no password auth) on each instance's `SSH_PORT` (localhost only)
- Instances are directories: `config/<instance>/` (gitignored) holds `.env`, an optional `docker-compose.override.yml`, and optional build-time scripts under `install/`. There is no default instance and no inheritance between instances; `build`, `start` and `dev` take the instance name as their first argument
- This repository must live outside every container mount: the host runs its scripts and reads its config and `.git`. `start` pipes `docker compose config --format json`, and `docker inspect` of a running container, to `scripts/check-repo-mounts` (Python, so `python3` is required on the host), which rejects any bind source, Compose `secrets`/`configs` file, or named volume whose local driver binds an absolute device (from `driver_opts`, or `docker volume inspect` for external and running-container volumes) that is the repo, an ancestor, or a descendant other than exactly `data/<instance>`, and rejects `volumes_from`, a symlinked `data/<instance>`, and external or running-container volumes it cannot inspect (it fails closed). Missing sources are canonicalized through their deepest existing ancestor, since Docker creates them; on macOS paths are compared case-insensitively. Start containers only through `./start`; a hand-run `docker compose up` is not checked. Covered by `tests/check-repo-mounts.sh`, `tests/env-loading.sh` and real Compose output in `tests/compose-build-targets.sh`. Edit this repo on the host, or in a separate clone inside `CODE_DIR` that is pushed and pulled into the host copy through the remote (never fetched by path)
- Code directory is volume-mounted at the same path inside and outside the container; host path (`CODE_DIR`) is passed into the container as `$CODE_DIR` for Docker socket compatibility
- Every Compose call gets its inputs from `set_compose_args` in `scripts/env.sh`: `--env-file config/<instance>/.env` (so Compose never auto-loads a root `.env`), `docker-compose.yml`, the instance override if present, and `docker-compose.docker-socket.yml` when enabled. `COMPOSE_FILE` is rejected
- Host Docker socket is mounted only when `DANGEROUSLY_MOUNT_DOCKER_SOCKET=true`. The socket is root-equivalent host access, so leave it off for isolated instances. `start` leaves a running container alone but exits with an error if its socket mount disagrees with the setting; start containers only through `./start`, since a hand-run `docker compose up` omits the socket file
- Installs dotfiles from https://github.com/pauldowman/dotfiles
- Includes neovim, Claude CLI, tmux, zsh, fzf, ripgrep, fd (Ubuntu's `fd-find`, symlinked to `fd` in `/usr/local/bin`), mise, and dev tools
- Agent CLIs are installed user-scope in the image because they self-update in place during a container's lifetime; runtime updates disappear on recreation unless their paths are deliberately listed in `data/<instance>/persist`. Codex uses OpenAI's standalone installer, with `~/.local/bin/codex` targeting its user-writable package under `~/.codex/packages/standalone`; do not advertise `auth.json` as persistent without an authenticated rewrite test. Other npm globals remain system-scope under `/usr/local` so rebuilds refresh them.

## Key files

- `Dockerfile` — multi-stage image build. The final/default `base` target is SSH-only; the opt-in `gui` target adds XFCE4 + xrdp. The xrdp/GUI login password is the username (`chpasswd`). The GUI stage wires `pam_gnome_keyring` into `/etc/pam.d/xrdp-sesman` so the GNOME login keyring is created/unlocked with that login password at login. Keyring files are ephemeral unless their paths are listed in `data/<instance>/persist`; applications may atomically replace them, so persistence is not guaranteed without an application-specific test. If stale selected files cause an unknown-password prompt, remove their counterparts from `data/<instance>/home/.local/share/keyrings` and re-login. The GUI stage also installs Python GI/AT-SPI, GTK 3/GDK, xdotool and xprop for existing-desktop agent control; discover the live display/session bus rather than persisting their addresses. `scripts/desktop-accessibility.desktop` is installed under `/etc/xdg/autostart` and sets `org.a11y.Status.IsEnabled` on GUI login without changing `ScreenReaderEnabled`. Bus-environment equality and registry reachability do not prove selected-application controls; inspect the actual accessibility tree. The switch is backed by GSettings when available, while container recreation discards unlisted home settings. The GUI stage installs Google Chrome (Google ships both amd64 and arm64 Linux debs) and makes it XFCE's preferred browser through a system-wide `chrome-nosandbox` helper, because Docker's default seccomp profile blocks the namespaces Chrome's sandbox needs and a sandboxed launch from `xdg-open` crashes.
- `docker-compose.yml` — runs the container without a home volume; reads `USERNAME`, `SSH_AUTHORIZED_KEYS`, and `CODE_DIR` from env and tags each image by instance and build target. `INSTANCE` is required (`${INSTANCE:?}`), `config/<instance>/install` is the build's `instance-install` named context (the only instance files the build sees), and `data/<instance>` is mounted at `/var/lib/dev-container/data`. Sets `shm_size: 1gb` for every target because Docker's 64MB default `/dev/shm` breaks Chrome renderers and multiprocessing workloads; tmpfs only consumes memory that is actually written.
- `scripts/start.sh` — container entrypoint: uses the instance data mounted at `/var/lib/dev-container/data`, creates its `home` with runtime-user ownership, links the paths listed in its `persist` into `$HOME`, copies its `certs`, writes runtime-managed SSH files, sets up Docker socket access, and starts sshd
- `scripts/docker-shim` — installed as `/usr/local/bin/docker` (shadows the real `/usr/bin/docker`). **macOS-host only:** on a Mac, the `/Users -> /home` symlink means path-canonicalizing tools (notably `cargo-prove --docker`) pass an unshared `/home/...` bind source that Docker Desktop rejects. The shim rewrites bind-mount sources to the shared host path, derived from `/proc/self/mountinfo`. No-op on Linux hosts (no Docker Desktop shared mounts).
- `scripts/ssh-agent-relink` — preserves `~/.ssh/agent.sock` only when its agent contains the key matching the startup-managed `~/.ssh/id_ed25519.pub`; dead, empty and wrong-key targets trigger a search of other forwarded sockets. An empty agent is reachable but cannot sign. Called silently from `scripts/ssh-rc` and a 60s startup watchdog. Regression tests use real temporary agents in `tests/ssh-agent-relink.py`; optional link/key-file arguments keep them isolated. The host `dev` launcher loads empty agents or replaces unreachable ones before connecting, covered by `tests/dev-agent.py`.
- `config/<instance>/install/custom-install-user.sh` (and `custom-install-root.sh`) — optional per-instance setup, run as the user at **image build time** (`Dockerfile`) with `bash -eo pipefail`, so any failing command fails the build (both custom scripts were once silently swallowed by `|| true`). There is no TTY, so commands must be non-interactive (e.g. `npx -y skills@latest add -g -y …`). Its writes under `$HOME` land in the image and appear in newly created containers. Build time has no GitHub credentials—`dev` forwards `GH_TOKEN` only for SSH sessions—so anything pulling from a private repository cannot run here. Setup needing credentials belongs in `config/<instance>/first-connect.sh`.
- `config/<instance>/first-connect.sh` — optional setup needing `GH_TOKEN`, run by `dev <instance> <session>` before attaching tmux, once per container: a marker in `~/.cache/dev-container` records success, so rebuild to rerun. The setup ssh call has no `-L`/`-A`, sends the script on stdin, and runs it under a non-blocking `flock` with `bash -eo pipefail` from `$SHELL -lic`, so it gets the user's login-shell environment without the framework knowing their shell config. Failure warns and still connects. Covered by `tests/dev-first-connect.sh`, whose ssh stub runs the remote command locally
- `scripts/start-gui.sh` — GUI entrypoint: same as start.sh but also starts xrdp
- `docker-compose.docker-socket.yml` — the optional Docker socket mount, added by `start` when `DANGEROUSLY_MOUNT_DOCKER_SOCKET=true`
- `scripts/env.sh` — shared by `build`, `start` and `dev`: `select_instance` validates the name (two or more characters, as Compose requires for container names), clears the instance-controlled variables inherited from the caller's shell (so an exported `GH_TOKEN` or `DANGEROUSLY_MOUNT_DOCKER_SOCKET` cannot leak into an instance), and loads only `config/<instance>/.env`; `set_compose_args` builds the Compose arguments
- `build` — shell script that stops the selected container and rebuilds its image via Docker Compose; run `./start <instance>` afterward

## Build & run

```sh
# Rebuild and restart
./build <instance>
./start <instance>

# Build and start the opt-in GUI target after setting BUILD_TARGET=gui in config/<instance>/.env
./build <instance>
./start <instance>
```

`./build` and `./start` validate `BUILD_TARGET`; supported values are `base` (the default) and `gui`. A configured legacy `DOCKERFILE` value is rejected so it cannot silently select an obsolete build path.

Required env vars, in `config/<instance>/.env` (root `.env`, `.env.<instance>` and root overrides or custom scripts from the old layout are ignored):
- `USERNAME` — the container user (should match host username)
- `SSH_AUTHORIZED_KEYS` — newline-separated public keys; first key is also used as the user's public key
- `CODE_DIR` — canonical absolute path to the code directory (e.g. `/Users/paul/code`); symlink aliases are rejected because it is mounted at the same path inside the container and passed as `$CODE_DIR` for Docker-in-Docker volume paths

## Selective home persistence

The home directory is ephemeral across container recreation. Each instance has its own gitignored `data/<instance>/` in this repository, which `start` requires to exist and Compose mounts at the fixed path `/var/lib/dev-container/data`; no other part of the repository is mounted for it, so instances do not see each other's data; `start` enforces that the repository is outside every container mount. Persistence is one tree plus a list there: `home/` mirrors `$HOME`, and `persist` lists home-relative paths (one per line; blank lines, `#` comments and one trailing `/` allowed). At startup `link-home SOURCE_ROOT LIST_FILE DESTINATION_ROOT` makes each listed path a link `~/<path> -> /var/lib/dev-container/data/home/<path>`, file or directory, creating real parent directories. Unlisted content is ignored; a missing list persists nothing. CA certificates in `certs/` are copied into the image's CA directory on every start rather than bind-mounted, because the container can write `data/<instance>/` and a nested bind mount of a path it controls could be redirected by a symlink when the container is recreated.

The linker validates every entry before linking anything and names the list line in errors. It rejects absolute entries, empty/`.`/`..` components (so `.ssh//authorized_keys` cannot slip past the runtime-managed check), leading or trailing whitespace, duplicates, nested entries, missing sources, sources reached through a symlinked directory (a listed entry may itself be a symlink, even dangling), `.ssh/authorized_keys`, `.ssh/id_ed25519.pub`, `.ssh/agent.sock`, `.cache/dev-container` (the first-connect marker, which must not survive recreation), their descendants and ancestors (e.g. `.ssh`, `.cache`), entries mapping into or over the source root, destination parents that are symlinks or mountpoints, and destinations that are real directories (so list the narrowest path, e.g. `.claude/projects`, not an image-populated `.claude`). Tested in `tests/link-home.sh`; `tests/home-lifecycle.sh` shows two instances keep separate data.

Do not claim persistence for files an application updates by atomic rename because that can replace the destination symlink. Claude Code does this to `~/.claude/.credentials.json` on token refresh and login, so do not list it; Claude auth uses `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) exported in a listed `.zshrc.local`. Codex sessions are not persisted because resume also depends on versioned SQLite files and `~/.codex/packages` holds the image's Codex install. Unlisted home state is discarded on recreation, while code persists through `CODE_DIR`. `data/` is outside the build context and ignored by Git, but `git clean -fdx` can still delete it.

When the user asks to persist a home file or directory, set it up in the live container so no restart is needed. The instance's data is at `/var/lib/dev-container/data`. `rsync` is not installed; use `cp -a`.
- File: check whether the application replaces it by atomic rename (if so, warn and don't list it). Otherwise move it to `/var/lib/dev-container/data/home/<path>`, symlink `~/<path>` to that path, and append `<path>` to `/var/lib/dev-container/data/persist`.
- Directory, or a growing set of files: copy to `/var/lib/dev-container/data/home/<path>` with `cp -a`, then verify with `diff -rq` before switching. Then rename the original to `<path>.premigration`, replace it with a symlink to the copy, and append `<path>` to the list. Do this right after the copy, because writes between the copy and the rename are lost; don't copy again afterwards, since that would overwrite newer writes. Tell the user to delete `.premigration` after a rebuild confirms it works. Stop at the first failing command; zsh `eval` does not honor `set -e`, so chain the commands with `&&`.
- Confirm by running `/usr/local/bin/link-home /var/lib/dev-container/data/home /var/lib/dev-container/data/persist <empty scratch dir>` and inspecting the links.

When upgrading from the earlier layouts (a shared `data/home` where every file was persisted, directories in `data/dirs` behind relative symlinks), seed the list from the existing files and links, replace the `data/dirs` symlinks with the directories, then move `persist`, `home` and `certs` into `data/<instance>/`; `README.md` has the commands. When upgrading from the old named-home-volume configuration, persisted files must be copied into `data/<instance>/home` and listed before the first rebuild when possible. The old `<instance>_home` volume is left orphaned rather than deleted and can be mounted read-only for recovery. A linker validation error stops startup before sshd, so recovery must be performed from the host by inspecting `docker logs <instance>` and fixing the named `persist` line or `home` path.

## Connecting

Use the `dev` script to connect. It opens (or reattaches to) a named tmux session in `$CODE_DIR/<session-name>` and forwards the GitHub token:

```sh
./dev <instance> <session-name>   # e.g. ./dev work my-project
./dev <instance> list             # list active tmux sessions
```

The script finds the instance's published SSH port. To connect from a remote machine, SSH to the host and run the script there:

```sh
ssh -t dev <repo>/dev <instance> <session-name>
```

Port forwarding from the container is handled via `LocalForward` entries in the remote machine's `~/.ssh/config` for the host.

Run `eval "$(./dev --init)"` to enable zsh tab completion for instance names (from `config/`) and that instance's `CODE_DIR` subdirectories. Completion asks `dev <instance> --code-dir` in a subprocess so the instance `.env`, which holds `GH_TOKEN`, is never sourced into the interactive shell.
