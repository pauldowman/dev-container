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

## Configuration

The `.env` file is gitignored. Available options:

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

## Git Commit Signing

SSH commit signing works via the mounted SSH agent socket. Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
