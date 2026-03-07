# Dev Agent Container

This is a container for running claude code and codex safely. It has some opinionated and hardcoded things for me specifically.

## Setup

The script will build and run the containe the first time.

You will need to log in with claude or codex after rebuilding the container because `~/.claude` and `~/.claude.json` aren't shared with the host so that they don't conflict with the dotfiles that are installed.

## Usage

```bash
./safe-agent           # runs Claude (default)
./safe-agent claude    # runs Claude
./safe-agent codex     # runs Codex
./safe-agent shell     # runs zsh
```

Add to your PATH for convenience:

```bash
ln -s $(pwd)/safe-agent /usr/local/bin/safe-agent
```

The script:

- Automatically builds and starts the container if not running
- Sets the working directory to match your current directory (if under `/Users/paul/code`)
- Forwards your GitHub token for git operations
- Provides SSH agent access for commit signing

## Directory Mapping

| Host                    | Container               |
| ----------------------- | ----------------------- |
| `/Users/paul/code`      | `/workspace`            |
| `~/.ssh/id_signing.pub` | `~/.ssh/id_signing.pub` |
| `./data/certs/*.crt`    | Custom CA certificates  |

## Git Commit Signing

SSH commit signing works via the mounted SSH agent socket. Your signing key's public key is mounted into the container.

Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_signing.pub
git config --global commit.gpgsign true
```

## Custom CA Certificates

Place `.crt` files in `./data/certs/`. They are installed on container startup via `update-ca-certificates`.

## Pre-installed Tools

- **Languages**: Go 1.23, Rust 1.83, Node.js 22, Python 3.12
- **Language servers**: gopls, rust-analyzer, typescript-language-server
- **Blockchain**: Foundry (forge, cast, anvil, chisel)
- **CLI tools**: git, gh, jq, vim, fzf, ripgrep, zsh
- **AI assistants**: Claude Code, OpenAI Codex

Dotfiles are installed from https://github.com/pauldowman/dotfiles.git

## Rebuilding

```bash
docker compose down
docker compose build --no-cache
./safe-agent
```

Remember to run `claude login` after rebuilding.
