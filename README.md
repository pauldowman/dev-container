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

The instance name is used as the Docker Compose project name, container name, hostname, and part of the image tag. Image tags include both the instance and target, such as `dev-container:work-base` or `dev-container:work-gui`, so variants cannot overwrite one another. Each instance gets its own Docker-managed home volume, such as `work_home`, while sharing the same `CODE_DIR` mount.

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

## Session Persistence

tmux sessions don't survive a container rebuild, but their layout does: [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) are baked into the image and loaded from `/etc/tmux.conf`, so they apply only inside the container and don't require any plugin lines in your own tmux config (dotfiles stay portable to other machines).

Continuum auto-saves every 15 minutes while a client is attached, and auto-restores when the tmux server starts — so after a rebuild, the first `dev <session-name>` brings back all saved sessions with their windows, panes, layouts, and working directories (the session just created by `dev` keeps its fresh shell window alongside its restored ones). Running programs and shell history are not restored. Manual save is `prefix + Ctrl-s`, manual restore is `prefix + Ctrl-r`. Save files live under the home directory, which is a persistent volume.

## Configuration

The `.env` and `.env.<instance>` files are gitignored. Available options:

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_AUTHORIZED_KEYS` | Yes | — | One or more SSH public keys (newline-separated); the first is also written to `~/.ssh/id_ed25519.pub` for git commit signing |
| `USERNAME` | No | `$USER` | Username inside the container |
| `DOTFILES_REPO` | No | — | Git repo URL to clone and install as dotfiles |
| `DOTFILES_INSTALL_CMD` | No | `./install.sh` | Command to run inside the cloned dotfiles directory |
| `CODE_DIR` | Yes | — | Absolute host path to code directory (e.g. `/Users/paul/code`); mounted at the same path inside the container |
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

**`custom-install-user.sh`** — runs as the container user after dotfiles are installed. Use for personal tools, shell plugins, or user-level config. It runs at image build time, so writes under `$HOME` only reach a newly created `home` volume — rebuilding against an existing one won't re-apply them — and there are no GitHub credentials available. Anything that needs a token, or that must re-apply on every rebuild, has to be run by hand inside the container instead.

Example `custom-install-user.sh`:

```bash
# Install a mise plugin and tool version
mise use --global node@lts

# Add shell config
echo 'export MY_VAR=value' >> ~/.zshrc.local
```

## GUI Access

Set the validated `gui` build target persistently in `.env`, then build and start to get an XFCE4 desktop accessible via RDP:

```dotenv
BUILD_TARGET=gui
```

```bash
./build
./start
```

Connect with any RDP client to `localhost:3389`. The desktop is configured with dark mode and a single workspace by default.

## Directory Mapping

`CODE_DIR` is mounted at the same path inside the container. On Mac, `/Users` is symlinked to `/home` inside the container so that `~/code` resolves correctly regardless of the host path.

### Docker-outside-of-docker bind mounts (macOS only)

This applies only when the host is **macOS**; on a Linux host it has no effect.

The host Docker socket is mounted, so `docker` commands inside the container run against the host's Docker daemon. On a Mac, Docker Desktop resolves bind-mount *sources* against the **macOS host** filesystem and only shares certain roots (e.g. `/Users`). But because of the Mac-only `/Users -> /home` symlink above, the repo's *real* path inside the container is `/home/$USERNAME/...`. Tools that canonicalize a path before mounting it — notably `cargo-prove prove build --docker` — then pass the unshared `/home/...` source, and Docker Desktop denies the mount (`path ... is not shared from the host`).

To fix this transparently, `scripts/docker-shim` is installed as `/usr/local/bin/docker` (which precedes the real `/usr/bin/docker` on `PATH`). It derives the container-path → host-path map from `/proc/self/mountinfo` and rewrites only bind-mount *sources* to the shared host path before exec'ing the real docker. On a Linux host there is no Docker Desktop and nothing to remap, so the shim is a transparent pass-through. It never touches container-target paths, named volumes, or non-mount arguments.

The home directory (`/home/$USERNAME`) is backed by a named Docker volume (`dev-container_home` for the default instance), so shell history, caches, configs, and runtime-installed tools persist across container restarts and rebuilds. On first run, the volume is seeded from the image's home directory (dotfiles, etc.). Subsequent rebuilds will *not* overwrite the volume — to pick up new home-dir content from a rebuilt image, remove the volume first:

```bash
docker compose -p dev-container down
docker volume rm dev-container_home
./build
```

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
