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
| `HOST_CODE_DIR` | No | `~/code` | Host directory to mount as `~/code` in the container |
| `DOCKERFILE` | No | `Dockerfile` | Dockerfile to build (use `Dockerfile.gui` for GUI access) |
| `REMOTE_DEV_SERVER` | No | — | Hostname of a remote machine running the container, used as a jump host |
| `FORWARD_PORTS` | No | — | Comma-separated ports to forward from the container to your local machine |

## Customization

Two optional scripts can be created locally (both are gitignored):

**`custom-install-root.sh`** — runs as root after the toolchains are installed, before the user is created. Use for extra `apt` packages or system-level config.

**`custom-install-user.sh`** — runs as the container user after dotfiles are installed. Use for personal tools, shell plugins, or user-level config.

Example `custom-install-user.sh`:

```bash
# Install mise (version manager)
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc.local

# Install Claude plugins
$HOME/.local/bin/claude plugin marketplace add austintgriffith/ethskills
$HOME/.local/bin/claude plugin install ethskills
```

## GUI Access

Use `Dockerfile.gui` to get an XFCE4 desktop accessible via RDP:

```
DOCKERFILE=Dockerfile.gui
```

Connect with any RDP client to `localhost:3389`. The desktop is configured with dark mode and a single workspace by default.

## Remote Access

Set `REMOTE_DEV_SERVER` in `.env` to connect to a container running on a remote machine:

```
REMOTE_DEV_SERVER=my-dev-box
```

## Port Forwarding

Set `FORWARD_PORTS` in `.env` to forward ports from inside the container to your local machine:

```
FORWARD_PORTS=8000,3000
```

The ports will be available on `localhost` on your client machine. This works whether connecting directly or via a jump host.

## Directory Mapping

The host directory `HOST_CODE_DIR` (default: `~/code`) is mounted as `~/code` inside the container.

### Custom Mounts

To add extra mounts without modifying `docker-compose.yml`, copy `docker-compose.override.yml.example` to `docker-compose.override.yml` and edit it. The override file is gitignored so changes stay local.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
```

## Pre-installed Tools

### Languages & Runtimes
- Go (latest)
- Rust (latest stable)
- Node.js (latest)
- Python 3.12

### Language Servers
- gopls (Go)
- rust-analyzer, clippy (Rust)
- typescript-language-server (TypeScript/JavaScript)
- pyright (Python)
- solidity-language-server (Solidity)
- bash-language-server (Bash)

### CLI Tools
- git, gh, jq, vim, neovim, fzf, ripgrep, zsh, tmux
- just, make, direnv, bat, btop, glow
- tuicr, mise

### Blockchain
- Foundry: forge, cast, anvil, chisel

### AI Assistants
- Claude Code
- OpenAI Codex

## Custom CA Certificates

Place `.crt` files in `./data/certs/`. They are installed on container startup via `update-ca-certificates`.

## Git Commit Signing

SSH commit signing works via the mounted SSH agent socket. Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
