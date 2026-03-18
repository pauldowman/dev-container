# Dev Container

> [!NOTE]
> Despite the name, this is not a Dev Container per the [containers.dev](https://containers.dev) specification. It's a plain Docker container managed with Docker Compose.

A personal development container. Opinionated and hardcoded for my setup.

## Setup

Build the image and start the container:

```bash
./build
```

To rebuild the image and restart the container later, run `./build` again. To start the container without rebuilding, run `./start`.

Set up shell integration (adds the `dev` alias and tab completion):

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

Copy `.env.example` to `.env` and edit it:

```bash
cp .env.example .env
```

The `.env` file is gitignored. Available options:

- `SSH_AUTHORIZED_KEYS` — one or more SSH public keys to authorize for login (newline-separated); the first key is also written to `~/.ssh/id_ed25519.pub` for use with git commit signing
- `SSH_USERNAME` — username inside the container (defaults to your local `$USER`)
- `REMOTE_DEV_SERVER` — hostname of a remote machine running the container, used as a jump host
- `FORWARD_PORTS` — comma-separated ports to forward from inside the container to your local machine (e.g. `8000,3000`)

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

| Host     | Container  |
| -------- | ---------- |
| `~/code` | `~/code`   |

### Custom Mounts

To add extra mounts without modifying `docker-compose.yml`, copy `docker-compose.override.yml.example` to `docker-compose.override.yml` and edit it. The override file is gitignored so changes stay local.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
```

## Pre-installed Tools

### Languages & Runtimes
- Go 1.23
- Rust 1.83
- Node.js 22
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
- Claude Code (with ethskills plugin)
- OpenAI Codex

Dotfiles are installed from https://github.com/pauldowman/dotfiles.git

## Custom CA Certificates

Place `.crt` files in `./data/certs/`. They are installed on container startup via `update-ca-certificates`.

## Git Commit Signing

SSH commit signing works via the mounted SSH agent socket. Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```
