# Dev Container

> [!NOTE]
> Despite the name, this is not a Dev Container per the [containers.dev](https://containers.dev) specification. It's a plain Docker container managed with Docker Compose.

A Docker-based development environment with SSH access, supporting multiple language toolchains. Includes Go, Rust, Node.js, and Foundry (Ethereum), plus a full suite of CLI tools and language servers.

## Setup

Copy `.env.example` to `.env` and configure it:

```bash
cp .env.example .env
```

Build the image, then start the container:

```bash
./build
./start
```

To rebuild the image later, run `./build` again; it stops the existing container before building, so run `./start` afterward. To start the container without rebuilding, run only `./start`.

Set up shell integration (adds the `dev` command and tab completion):

```bash
eval "$(~/code/dev-container/dev --init)"
```

Add this to your `~/.zshrc` to load it automatically.

## Usage

```bash
dev <session-name>   # attach to or create a tmux session inside the container
dev list             # list running tmux sessions
```

Nested paths are supported:

```bash
dev projectname
dev subdir/projectname
```

The working directory inside the container is `~/code/<session-name>`.

### Multiple Instances

The default instance is named `dev-container` and uses SSH port `2222`. To run another instance, give it a unique instance name and SSH port:

```bash
./start --instance work --ssh-port 2223
dev --instance work projectname
dev --instance work list
```

The instance name is used as the Docker Compose project name, container name, hostname, and part of the image tag. Image tags include both the instance and target, such as `dev-container:work-base` or `dev-container:work-gui`, so variants cannot overwrite one another. Instances have separate ephemeral home directories while sharing the same `CODE_DIR` mount and the same explicitly selected files under this repository's `data/home` directory.

You can also set defaults with environment variables:

```bash
DEV_CONTAINER_INSTANCE=work SSH_PORT=2223 ./start
DEV_CONTAINER_INSTANCE=work dev projectname
```

For per-instance configuration, create `.env.<instance>`. The scripts load `.env` first for shared defaults, then load `.env.<instance>` for the selected instance if it exists. Explicit CLI flags, such as `--instance` and `--ssh-port`, take precedence.

```bash
# .env
USERNAME=paul
CODE_DIR=/home/paul/code

# .env.work
SSH_PORT=2223
FORWARD_PORTS=3000,5173
```

## tmux Session State

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) are baked into the image and loaded from `/etc/tmux.conf`, so they apply only inside the container and don't require plugin lines in your own tmux config. Continuum auto-saves every 15 minutes while a client is attached and auto-restores when the tmux server starts; manual save is `prefix + Ctrl-s`, and manual restore is `prefix + Ctrl-r`.

The saved layouts remain available across process and container restarts, but they are discarded when the container is recreated unless their exact files are selected through `data/home`. tmux-resurrect creates newly named state files, and new files are not automatically persistent under the file-level overlay, so this setup does not promise tmux layout restoration after a rebuild. Running programs and shell history are never restored by tmux-resurrect.

## Configuration

The `.env` and `.env.<instance>` files are gitignored. Available options:

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_AUTHORIZED_KEYS` | Yes | — | One or more SSH public keys (newline-separated); the first is also written to `~/.ssh/id_ed25519.pub` for git commit signing |
| `USERNAME` | No | `$USER` | Username inside the container |
| `DOTFILES_REPO` | No | — | Git repo URL to clone and install as dotfiles |
| `DOTFILES_INSTALL_CMD` | No | `./install.sh` | Command to run inside the cloned dotfiles directory |
| `CODE_DIR` | Yes | — | Existing canonical absolute host path containing this repository (e.g. `/Users/paul/code`); symlink aliases are rejected because it is mounted unchanged inside the container |
| `BUILD_TARGET` | No | `base` | Validated image target: `base` or `gui`; use `./build` and `./start` rather than invoking Compose directly |
| `TZ` | No | host TZ | Timezone inside the container (e.g. `America/New_York`) |
| `FORWARD_PORTS` | No | — | Comma-separated ports to forward from container to local machine (used by `./dev`) |
| `GH_TOKEN` | No | `gh auth token` | GitHub token forwarded into the container session (see [GitHub token](#github-token)) |
| `SSH_PORT` | No | `2222` | Host SSH port published by `./start`; use a unique port for each running instance |
| `DEV_CONTAINER_INSTANCE` | No | `dev-container` | Default instance name for `./build`, `./start`, and `./dev`; can be overridden with `--instance` |

## Default Config

The `defaults/` directory holds minimal default config files (tmux, zsh, Claude Code, Codex, tuicr) that are copied into the container user's home directory at build time. They give a usable baseline when no `DOTFILES_REPO` is set.

If `DOTFILES_REPO` is set, the dotfiles install runs *after* the defaults are copied and overwrites them (assuming the dotfiles install symlinks or writes to the same paths). To customize the defaults for everyone using this container, edit the files under `defaults/`; for personal config, use `DOTFILES_REPO`.

## Customization

Two optional scripts can be created locally (both are gitignored):

**`custom-install-root.sh`** — runs as root after the toolchains are installed, before the user is created. Use for extra `apt` packages or system-level config.

**`custom-install-user.sh`** — runs as the container user after dotfiles are installed. Use for personal tools, shell plugins, or user-level config. Its writes under `$HOME` are captured in the image and appear in each newly created container. Build time has no GitHub credentials, so anything pulling from a private repository cannot run here; setup requiring credentials belongs in a script run by hand inside the container, where its results remain ephemeral unless their exact files are selected through `data/home`.

Example `custom-install-user.sh`:

```bash
# Install a mise plugin and tool version
mise use --global node@lts

# Add shell config
echo 'export MY_VAR=value' >> ~/.zshrc.local
```

## GUI Access

Set the validated `gui` build target and append `3389` to any existing `FORWARD_PORTS` list, preferably in `.env.<instance>` when only one instance uses the GUI. Then build and start to get an XFCE4 desktop accessible via RDP:

```dotenv
BUILD_TARGET=gui
FORWARD_PORTS=3389
```

```bash
./build
./start
```

Start `./dev <session-name>` for an existing code directory and leave that SSH session open; `FORWARD_PORTS=3389` forwards xrdp from the container because Compose does not publish the RDP port directly. Then connect an RDP client to `localhost:3389`; both the xrdp username and password are the configured container username. Only one SSH session can bind that local port at a time. If port 3389 is already in use or two GUI instances must run concurrently, omit it from `FORWARD_PORTS` for the additional session and create a manual forward with a different local port, such as `ssh -N -L 3390:localhost:3389 -p 2222 <username>@localhost`, adjusting the username and SSH port for the instance; connect RDP to `localhost:3390` instead. The desktop is configured with dark mode and a single workspace by default. GNOME keyring files under `~/.local/share/keyrings` are ephemeral on container recreation unless exact files are selected under `data/home`; because keyring applications may replace files atomically, do not assume selecting them is reliable without application-specific testing. If a stale selected keyring causes an unknown-password prompt, remove its corresponding files from `data/home/.local/share/keyrings` and log in again.

## Directory Mapping

`CODE_DIR` is mounted at the same path inside the container. On Mac, `/Users` is symlinked to `/home` inside the container so that `~/code` resolves correctly regardless of the host path.

### Selective Home Persistence

The container home has no Docker volume. It survives an ordinary process or container restart, but a container recreation starts again from the image and discards home changes that were not explicitly selected. Code survives because `CODE_DIR` is host-mounted.

The only selective home-persistence source is the gitignored `data/home` directory in this repository. On startup, every regular file or source symlink below it is linked into the same home-relative path: `data/home/.config/tool/state.json` becomes `~/.config/tool/state.json`. Source directories only provide hierarchy, so empty directories have no effect and whole destination directories are never replaced. Every instance on the machine deliberately uses this one shared source, which means simultaneously running instances can contend over mutable selected files.

Before upgrading an installation that still uses the old named home volume, copy each file you want to retain into its exact `data/home` path before running the new `./build`; the build removes the old container, though it does not delete the named volume. Also ensure this repository is inside the canonical `CODE_DIR` configured in `.env`, remove any obsolete `DOCKERFILE` setting, and use `BUILD_TARGET=base` or `BUILD_TARGET=gui`. For example, run the following from the repository root while the old default container is still running:

```bash
container=dev-container
container_home="$(docker exec "$container" sh -c 'printf %s "$HOME"')"
mkdir -p data/home/.config/tool
docker cp "$container:$container_home/.config/tool/state.json" data/home/.config/tool/state.json
```

Inspect copied entries before rebuilding. Do not migrate a symlink unless its target will still exist after recreation; copy the underlying regular file instead when the old target lived only in the named home volume.

If the container was already rebuilt, the old Compose volume normally remains as `<instance>_home` (for example, `dev-container_home`). Locate it with `docker volume ls --filter name=_home`, then mount that exact volume read-only and copy only the files you intend to persist:

```bash
instance=dev-container
mkdir -p data/home/.config/tool
docker run --rm \
  --mount "type=volume,src=${instance}_home,dst=/old-home,readonly" \
  --mount "type=bind,src=$PWD/data/home,dst=/new-home" \
  ubuntu:24.04 sh -c 'mkdir -p /new-home/.config/tool && cp -a /old-home/.config/tool/state.json /new-home/.config/tool/state.json'
sudo chown -R "$(id -u):$(id -g)" data/home/.config/tool
```

Verify the copied files and the rebuilt container before optionally removing the old volume with `docker volume rm "${instance}_home"`; that deletion is permanent. The obsolete `dev-container:latest` image can likewise be removed with `docker image rm dev-container:latest` after confirming no container still uses it.

To opt in an existing file, move it to its exact path under `data/home`, then restart the container so startup creates the link. For example, run the following on the host from this repository; replace `dev-container` with a named instance when needed:

```bash
docker exec dev-container sh -c 'mkdir -p "$DEV_CONTAINER_REPO_DIR/data/home/.config/tool" && mv "$HOME/.config/tool/state.json" "$DEV_CONTAINER_REPO_DIR/data/home/.config/tool/state.json"'
docker restart dev-container
```

Persistence is file-grained. If an application updates a file by atomically renaming a replacement over it, the symlink can be lost and later writes remain only in the ephemeral home. Newly named state files are not automatically selected merely because another file in the same directory is selected. Verify application behavior before relying on this mechanism for important state.

Startup refuses to select `data/home/.ssh/authorized_keys`, `data/home/.ssh/id_ed25519.pub`, `data/home/.ssh/agent.sock`, or anything below those paths because the runtime manages them. Other unlisted files—including shell history, caches, credentials, and runtime-installed tools—are discarded on container recreation. `data/` is excluded from both Git and the Docker build context, but it is still ordinary ignored machine data: commands such as `git clean -fdx` can permanently delete it.

If a selected path prevents startup, inspect `docker logs <instance>` from the host. Fix or remove the named entry under `data/home`, then restart the container; SSH cannot become available until every selected mapping passes validation.

### Docker-outside-of-docker bind mounts (macOS only)

This applies only when the host is **macOS**; on a Linux host it has no effect.

The host Docker socket is mounted, so `docker` commands inside the container run against the host's Docker daemon. On a Mac, Docker Desktop resolves bind-mount *sources* against the **macOS host** filesystem and only shares certain roots (e.g. `/Users`). But because of the Mac-only `/Users -> /home` symlink above, the repo's *real* path inside the container is `/home/$USERNAME/...`. Tools that canonicalize a path before mounting it — notably `cargo-prove prove build --docker` — then pass the unshared `/home/...` source, and Docker Desktop denies the mount (`path ... is not shared from the host`).

To fix this transparently, `scripts/docker-shim` is installed as `/usr/local/bin/docker` (which precedes the real `/usr/bin/docker` on `PATH`). It derives the container-path → host-path map from `/proc/self/mountinfo` and rewrites only bind-mount *sources* to the shared host path before exec'ing the real docker. On a Linux host there is no Docker Desktop and nothing to remap, so the shim is a transparent pass-through. It never touches container-target paths, named volumes, or non-mount arguments.

### Custom Mounts

To add extra mounts without modifying `docker-compose.yml`, copy `docker-compose.override.yml.example` to `docker-compose.override.yml` and edit it. The override file is gitignored so changes stay local.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
```

## Pre-installed Tools

See the [Dockerfile](Dockerfile) for the full list. Highlights:

- **Languages:** Go, Rust, Node.js, Python
- **Language servers:** gopls, rust-analyzer, typescript-language-server, pyright, solidity-language-server, bash-language-server
- **CLI:** git, gh, docker, gcloud, neovim, tmux, fzf, ripgrep, just, direnv, mise, glow, and others
- **Kubernetes & cloud:** kubectl, kubie, gke-gcloud-auth-plugin, gcx (Grafana CLI)
- **Blockchain:** Foundry (forge, cast, anvil, chisel)
- **AI:** Claude Code, OpenAI Codex

Codex is installed with OpenAI's standalone installer as the container user. The command is `~/.local/bin/codex`, its user-writable package is under `~/.codex/packages/standalone`, and `/etc/zsh/zshenv` exposes the command to interactive and non-interactive zsh sessions without changing npm's `/usr/local` global prefix. Individual Codex-adjacent files can coexist with that package through the file-level `data/home` overlay, but `auth.json` is not documented as safely persistable because no authenticated rewrite test proves Codex preserves its symlink.

## Custom CA Certificates

Place `.crt` files in `./data/certs/`. They are installed on container startup via `update-ca-certificates`.

## GitHub token

The `./dev` script forwards a GitHub token into the container as `$GH_TOKEN` so `gh` and other tools work without a separate login inside the container.

By default it calls `gh auth token` on the host, which typically returns a broadly-scoped token. Prefer setting `GH_TOKEN` in `.env` to a [fine-grained PAT](https://github.com/settings/personal-access-tokens/new) limited to just the repos and permissions you need. If `GH_TOKEN` is unset, `./dev` prints a warning and falls back to `gh auth token`.

Suggested permissions for a token that can push, work with PRs and issues, manage Projects v2, and debug CI:

**Repository permissions:**

| Permission | Level | Covers |
|---|---|---|
| Metadata | Read | Mandatory for all fine-grained tokens |
| Contents | Read & write | `git push`, reading files via API |
| Pull requests | Read & write | View / open / edit / comment on PRs |
| Issues | Read & write | View / open / edit / comment on issues |
| Actions | Read | Workflow runs, jobs, logs — used to debug failing CI |
| Commit statuses | Read | Only needed for non-Actions CI (CircleCI, etc.) |
| Workflows | Read & write | Only needed if pushing changes to `.github/workflows/*.yml` |

**Organization or Account permissions** (depending on where your Projects v2 board lives):

| Permission | Level | Covers |
|---|---|---|
| Projects | Read & write | Query and update Projects v2 boards |

## Git Commit Signing

SSH commit signing works via the forwarded SSH agent. Each connection's forwarded socket is symlinked to the stable path `~/.ssh/agent.sock` (which all shells use), and `ssh-agent-relink` re-points the link whenever its target dies — on each new connection via `~/.ssh/rc`, and within a minute via a watchdog loop in the container entrypoint — so the agent keeps working as SSH sessions come and go, as long as at least one connection with agent forwarding is alive.

Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
