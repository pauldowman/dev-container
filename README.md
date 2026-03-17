# Dev Container

> [!NOTE]
> Despite the name, this is not a Dev Container per the [containers.dev](https://containers.dev) specification. It's a plain Docker container managed with Docker Compose.

A personal development container. Opinionated and hardcoded for my setup.

## Setup

Build the image:

```bash
./build
```

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

## Remote Access

The `dev` script can connect to a container running on a remote machine. Set `REMOTE_DEV_SERVER` to the hostname of the machine running the container and it will be used as a jump host:

```bash
export REMOTE_DEV_SERVER=my-dev-box
dev projectname
```

Add the export to your `~/.zshrc` to make it permanent.

## Directory Mapping

| Host     | Container  |
| -------- | ---------- |
| `~/code` | `~/code`   |

### Custom Mounts

To add extra mounts without modifying `docker-compose.yml`, copy `docker-compose.override.yml.example` to `docker-compose.override.yml` and edit it. The override file is gitignored so changes stay local.

```bash
cp docker-compose.override.yml.example docker-compose.override.yml
```

## Starting the Container

The `start` script starts the container if it isn't already running:

```bash
./start
```

The `build` script rebuilds the image and restarts the container:

```bash
./build
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
git config --global user.signingkey ~/.ssh/id_signing.pub
git config --global commit.gpgsign true
```
