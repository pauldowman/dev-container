# Dev Container

> [!NOTE]
> Despite the name, this is not a Dev Container per the [containers.dev](https://containers.dev) specification. It's a plain Docker container managed with Docker Compose.

A Docker-based development environment with SSH access, supporting multiple language toolchains. Includes Go, Rust, Node.js, and Foundry (Ethereum), plus a full suite of CLI tools and language servers.

## Setup

Copy `.env.example` to `.env` and configure it:

```bash
cp .env.example .env
```

Build the image and start the container:

```bash
./build
```

To rebuild the image and restart the container later, run `./build` again. To start the container without rebuilding, run `./start`.

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

The instance name is used as the Docker Compose project name, container name, and hostname. Each instance gets its own Docker-managed home volume, such as `work_home`, while sharing the same image and `CODE_DIR` mount.

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

## Configuration

The `.env` and `.env.<instance>` files are gitignored. Available options:

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_AUTHORIZED_KEYS` | Yes | — | One or more SSH public keys (newline-separated); the first is also written to `~/.ssh/id_ed25519.pub` for git commit signing |
| `USERNAME` | No | `$USER` | Username inside the container |
| `DOTFILES_REPO` | No | — | Git repo URL to clone and install as dotfiles |
| `DOTFILES_INSTALL_CMD` | No | `./install.sh` | Command to run inside the cloned dotfiles directory |
| `CODE_DIR` | Yes | — | Absolute host path to code directory (e.g. `/Users/paul/code`); mounted at the same path inside the container |
| `DOCKERFILE` | No | `Dockerfile` | Dockerfile to build (use `Dockerfile.gui` for GUI access) |
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

**`custom-install-user.sh`** — runs as the container user after dotfiles are installed. Use for personal tools, shell plugins, or user-level config.

Example `custom-install-user.sh`:

```bash
# Install a mise plugin and tool version
mise use --global node@lts

# Add shell config
echo 'export MY_VAR=value' >> ~/.zshrc.local
```

## GUI Access

Use `Dockerfile.gui` to get an XFCE4 desktop accessible via RDP:

```
DOCKERFILE=Dockerfile.gui
```

Connect with any RDP client to `localhost:3389`. The desktop is configured with dark mode and a single workspace by default.

## Directory Mapping

`CODE_DIR` is mounted at the same path inside the container. On Mac, `/Users` is symlinked to `/home` inside the container so that `~/code` resolves correctly regardless of the host path.

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

SSH commit signing works via the mounted SSH agent socket. Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
