# Dev Agent Container
This is a container for running claude code and codex safely. It has some opinionated and hardcoded things for me specifically.

## Setup

Build the image:

```bash
./build
```

The build script creates the image with your username and home directory code path baked in as build-time arguments.

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

- Runs a fresh ephemeral container each invocation (`docker run`, not `docker exec`)
- Sets the working directory to match your current directory
- Mounts `~/.claude` and `~/.claude.json` from the host (no login needed after rebuild)
- Forwards your GitHub token for git operations
- Provides SSH agent access for commit signing (automatically runs `ssh-add` for `~/.ssh/id_signing`)

## Directory Mapping

| Host                    | Container               |
| ----------------------- | ----------------------- |
| `~/code`                | `~/code` (same path)    |
| `~/.claude`             | `~/.claude`             |
| `~/.claude.json`        | `~/.claude.json`        |
| `~/.codex`              | `~/.codex`              |
| `~/.ssh/id_signing.pub` | `~/.ssh/id_signing.pub` |
| `./data/certs/*.crt`    | Custom CA certificates  |

## Claude Permissions

The container does not use `--dangerously-skip-permissions`. Instead, configure permissions via `~/.claude/settings.json` on the host (it's mounted into the container). For example:

```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(*)",
      "Read",
      "Edit",
      "Write",
      "NotebookEdit",
      "Mcp:*",
      "Fetch(*)",
      "WebSearch"
    ],
    "deny": [
      "Bash(git push *)",
      "Bash(git checkout *)",
      "Bash(git switch *)"
    ]
  },
  "hooks": {}
}
```

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
./build
```

Since `~/.claude` is mounted from the host, no re-login is needed after rebuilding.
