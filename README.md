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

The `dev` script works whether you run it locally on the machine running the container, or from a remote machine over SSH. If `~/code/.edit-locally` is not present, it SSHs to the host named `dev` and runs the container there.

Nested paths are supported:

```bash
dev projectname
dev subdir/projectname
```

The working directory inside the container is `/workspace/code/<session-name>`.

## Directory Mapping

| Host     | Container         |
| -------- | ----------------- |
| `~/code` | `/workspace/code` |

## Pre-installed Tools

- **Languages**: Go 1.23, Rust 1.83, Node.js 22, Python 3.12
- **Language servers**: gopls, rust-analyzer, typescript-language-server, pyright
- **Blockchain**: Foundry (forge, cast, anvil, chisel)
- **CLI tools**: git, gh, jq, vim, fzf, ripgrep, zsh, tmux
- **AI assistants**: Claude Code, OpenAI Codex

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
