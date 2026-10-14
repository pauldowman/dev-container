# Dev Container

> [!NOTE]
> Despite the name, this is not a Dev Container per the [containers.dev](https://containers.dev) specification. It's a plain Docker container managed with Docker Compose.

A Docker-based development environment with SSH access, supporting multiple language toolchains. Includes Go, Rust, Node.js, and Foundry (Ethereum), plus a full suite of CLI tools and language servers.

## Setup

Clone this repository outside your code directory and outside anything else you mount into a container, for example to `~/dev-container`. Your host runs its scripts and reads its configuration and `.git`, so a container that could write to it could get code run on your host. `./start` checks the Compose configuration and refuses to start while any mount exposes the repository; the only part a container sees is its own `data/<instance>/`. `./start` needs `python3` on the host for this check (on macOS it comes with the Command Line Tools). Start containers only through `./start`: a hand-run `docker compose up` is not checked.

To change this repository, edit it on the host, or work in a separate clone inside your code directory, push from there, and pull into the host copy through the remote. Don't fetch into the host copy directly from the in-container clone's path, since that runs `git` on the host against a repository containers can write.

Each instance is a directory under the gitignored `config/`; its name is the instance name. Create one by copying `.env.example` into it and configuring it:

```bash
mkdir -p config/work data/work
cp .env.example config/work/.env
```

Build the image, then start the container, passing the instance name:

```bash
./build work
./start work
```

To rebuild the image later, run `./build work` again; it stops the existing container before building, so run `./start work` afterward. To start the container without rebuilding, run only `./start work`.

Set up shell integration (adds the `dev` command and tab completion):

```bash
eval "$(~/dev-container/dev --init)"
```

Add this to your `~/.zshrc` to load it automatically.

## Usage

```bash
dev <instance> <session-name>   # attach to or create a tmux session inside the container
dev <instance> list             # list running tmux sessions
```

Nested paths are supported:

```bash
dev work projectname
dev work subdir/projectname
```

The working directory inside the container is `$CODE_DIR/<session-name>`.

### Multiple Instances

Every instance is self-contained: `config/<instance>/` holds its `.env`, an optional `docker-compose.override.yml`, and optional build-time scripts under `install/`. Nothing is inherited between instances, so settings such as `USERNAME` and `SSH_AUTHORIZED_KEYS` are repeated in each `.env`. Give each instance that runs at the same time a unique `SSH_PORT`.

```
config/
  work/
    .env
    docker-compose.override.yml
    install/custom-install-user.sh
  personal/
    .env
```

The instance name is used as the Docker Compose project name, container name, hostname, and part of the image tag. Image tags include both the instance and target, such as `dev-container:work-base` or `dev-container:work-gui`, so variants cannot overwrite one another. Instances have separate ephemeral home directories and separate persisted data in `data/<instance>/` (see [Selective Home Persistence](#selective-home-persistence)).

`./start <instance> --ssh-port <port>` overrides the instance's `SSH_PORT` for one start.

Upgrading from the old layout: root `.env`, `.env.<instance>`, `docker-compose.override*.yml` and `custom-install-*.sh` files are no longer read, and are no longer gitignored. Move them into `config/<instance>/` (custom scripts under `install/`), merging any `.env.<instance>` and per-instance override into that instance's copy, then delete the root files.

## tmux Session State

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) are baked into the image and loaded from `/etc/tmux.conf`, so they apply only inside the container and don't require plugin lines in your own tmux config. Continuum auto-saves every 15 minutes while a client is attached and auto-restores when the tmux server starts; manual save is `prefix + Ctrl-s`, and manual restore is `prefix + Ctrl-r`.

The saved layouts remain available across process and container restarts, but they are discarded when the container is recreated unless their directory is listed in `data/<instance>/persist`. This setup does not list it by default, so it does not promise tmux layout restoration after a rebuild. Running programs and shell history are never restored by tmux-resurrect.

## Configuration

Each instance's settings live in `config/<instance>/.env`, which is gitignored with the rest of `config/`. Available options:

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_AUTHORIZED_KEYS` | Yes | — | One or more SSH public keys (newline-separated); the first is also written to `~/.ssh/id_ed25519.pub` for git commit signing |
| `USERNAME` | No | `$USER` | Username inside the container |
| `DOTFILES_REPO` | No | — | Git repo URL to clone and install as dotfiles |
| `DOTFILES_INSTALL_CMD` | No | `./install.sh` | Command to run inside the cloned dotfiles directory |
| `CODE_DIR` | Yes | — | Existing canonical absolute host path of your code directory (e.g. `/Users/paul/code`); symlink aliases are rejected because it is mounted unchanged inside the container |
| `BUILD_TARGET` | No | `base` | Validated image target: `base` or `gui`; use `./build` and `./start` rather than invoking Compose directly |
| `TZ` | No | host TZ | Timezone inside the container (e.g. `America/New_York`) |
| `FORWARD_PORTS` | No | — | Comma-separated ports to forward from container to local machine (used by `./dev`); use `local:container` to forward to a different local port, e.g. `3390:3389` |
| `GH_TOKEN` | No | `gh auth token` | GitHub token forwarded into the container session (see [GitHub token](#github-token)) |
| `DANGEROUSLY_MOUNT_DOCKER_SOCKET` | No | `false` | `true` mounts the host Docker socket so `docker` works inside the container; this grants host-level access (see [Docker access](#docker-access)) |
| `SSH_PORT` | No | `2222` | Host SSH port published by `./start`; use a unique port for each running instance |

## Default Config

The `defaults/` directory holds minimal default config files (tmux, zsh, Claude Code, Codex, tuicr) that are copied into the container user's home directory at build time. They give a usable baseline when no `DOTFILES_REPO` is set.

If `DOTFILES_REPO` is set, the dotfiles install runs *after* the defaults are copied and overwrites them (assuming the dotfiles install symlinks or writes to the same paths). To customize the defaults for everyone using this container, edit the files under `defaults/`; for personal config, use `DOTFILES_REPO`.

## Customization

Two optional scripts can be created per instance under `config/<instance>/install/` (gitignored with the rest of `config/`). Only that `install/` directory is visible to the image build, so the instance `.env` is not. Each runs with `bash -eo pipefail`, so any failing command fails the build; append `|| true` to a command that is allowed to fail. Commands must not prompt, because the build has no TTY.

**`custom-install-root.sh`** — runs as root after the toolchains are installed, before the user is created. Use for extra `apt` packages or system-level config.

**`custom-install-user.sh`** — runs as the container user after dotfiles are installed. Use for personal tools, shell plugins, or user-level config. Its writes under `$HOME` are captured in the image and appear in each newly created container. Build time has no GitHub credentials, so anything pulling from a private repository cannot run here; put setup requiring credentials in the first-connect script below.

Example `config/<instance>/install/custom-install-user.sh`:

```bash
# Install a mise plugin and tool version
mise use --global node@lts

# Install agent skills globally (-y on both npx and skills avoids prompts)
npx -y skills@latest add -g -y pauldowman/cross-agent-review
```

Don't write `~/.zshrc.local` here: if `.zshrc.local` is listed in `data/<instance>/persist`, startup replaces the image's copy with a link to `data/<instance>/home/.zshrc.local`. Put shell config in your dotfiles or in a persisted `.zshrc.local`.

### First-connect script

`config/<instance>/first-connect.sh` (copy `first-connect.sh.example`) is for setup that needs GitHub credentials, such as installing plugins from private repositories. `dev <instance> <session>` runs it once per container, before attaching tmux, with `GH_TOKEN` set. It runs with `bash -eo pipefail`, started from your login shell (`$SHELL -lic`), so it sees whatever your shell config exports, such as `CLAUDE_CODE_OAUTH_TOKEN`. Its output appears on the first connect after a rebuild.

The container's home records a successful run, so the script runs again only after the container is recreated; rebuild to rerun it after editing. If it fails, `dev` prints a warning and still connects, and the next connect retries. Make it safe to rerun, and exit non-zero when setup is incomplete so it is retried. A connect that finds the script already running in another session skips it. The script stays in host-side `config/`; `dev` copies it into the container for each run.

## GUI Access

Set the validated `gui` build target and append `3389` to any existing `FORWARD_PORTS` list, in the instance's `config/<instance>/.env`. Then build and start to get an XFCE4 desktop accessible via RDP:

```dotenv
BUILD_TARGET=gui
FORWARD_PORTS=3389
```

```bash
./build work
./start work
```

Start `./dev work <session-name>` for an existing code directory and leave that SSH session open; `FORWARD_PORTS=3389` forwards xrdp from the container because Compose does not publish the RDP port directly. Then connect an RDP client to `localhost:3389`; both the xrdp username and password are the configured container username. Only one SSH session can bind that local port at a time. If port 3389 is already in use or two GUI instances must run concurrently, give each instance a different local port in its `config/<instance>/.env`, such as `FORWARD_PORTS=3390:3389`, and connect RDP to `localhost:3390` instead. The desktop is configured with dark mode and a single workspace by default. GNOME keyring files under `~/.local/share/keyrings` are ephemeral on container recreation unless their paths are listed in `data/<instance>/persist`; because keyring applications may replace files atomically, do not assume persisting them is reliable without application-specific testing. If a stale persisted keyring causes an unknown-password prompt, remove its corresponding files from `data/<instance>/home/.local/share/keyrings` and log in again.

The GUI target includes `/etc/xdg/autostart/desktop-accessibility.desktop`, which enables `org.a11y.Status.IsEnabled` on the real GUI session bus at login for native accessibility/agent observation. It leaves `ScreenReaderEnabled` unchanged. AT-SPI saves the setting through GSettings/dconf when its schema is available, so it survives logout and login. Container recreation discards settings whose paths are not listed in `data/<instance>/persist`; the autostart entry turns accessibility on again at each GUI login. Launch applications after login so they see the enabled switch. Verify actual application controls as well as the switch: a reachable registry or a registered window frame does not establish a usable browser/page tree. A browser can find the session bus without an exported `DBUS_SESSION_BUS_ADDRESS`; comparing environment variables does not verify accessibility. To check the switch, run `gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus --method org.freedesktop.DBus.Properties.Get org.a11y.Status IsEnabled` from the GUI session.

The GUI target installs Google Chrome (amd64 or arm64, matching the image) as XFCE's preferred web browser and launches it with `--no-sandbox`. Docker's default seccomp profile blocks the namespaces Chrome's sandbox needs, so without that flag, links opened from apps through `xdg-open` fail with "Failed to launch preferred application". Chrome shows a warning bar about the unsupported flag; that is expected.

## Directory Mapping

`CODE_DIR` is mounted at the same path inside the container. On Mac, `/Users` is symlinked to `/home` inside the container so that `~/code` resolves correctly regardless of the host path.

### Selective Home Persistence

The container home has no Docker volume. It survives an ordinary process or container restart, but a container recreation starts again from the image and discards home changes that were not explicitly persisted. Code survives because `CODE_DIR` is host-mounted.

Each instance has its own data directory, `data/<instance>/` in this repository (gitignored), which must exist before `./start <instance>`. It is mounted at `/var/lib/dev-container/data` in that instance's container only, so instances do not see each other's data; `./start` refuses to run while this repository is inside a container mount such as `CODE_DIR`. Persistence is one tree plus a list inside it:

- `data/<instance>/home/` mirrors your home directory and holds the persisted files and directories, e.g. `data/<instance>/home/.config/tool/state.json` or the directory `data/<instance>/home/.claude/projects`.
- `data/<instance>/persist` lists the home-relative paths to persist, one per line. Blank lines and lines starting with `#` are ignored, and a trailing `/` is allowed.

```
# data/<instance>/persist
.zshrc.local
.config/tool/state.json
.claude/projects/
```

On startup, each listed path becomes a link `~/<path> -> /var/lib/dev-container/data/home/<path>`, whether it is a file or a directory; parent directories in your home are created as real directories. Anything in `data/<instance>/home` that is not listed is ignored, and a missing `data/<instance>/persist` persists nothing. Containers of the same instance share its data directory, so simultaneously running ones can contend over mutable persisted files.

Startup validates the whole list before linking anything and stops with an error naming the list line when an entry:

- is absolute, has an empty, `.` or `..` component, or has leading or trailing whitespace;
- duplicates or is nested inside another entry;
- does not exist under `data/<instance>/home`, or is reached through a symlinked directory there (a listed entry may itself be a symlink);
- is `.ssh/authorized_keys`, `.ssh/id_ed25519.pub` or `.ssh/agent.sock`, something below them, or a directory containing them such as `.ssh`, because startup manages those files;
- would replace a real directory in the image's home. List the narrowest path instead, e.g. `.claude/projects` rather than `.claude`.

If a listed path prevents startup, inspect `docker logs <instance>` from the host, fix the named line in `data/<instance>/persist` or the named path under `data/<instance>/home`, then restart the container; SSH cannot become available until the whole list passes validation.

To persist an existing file or directory, move it to the same path under `data/<instance>/home`, add the path to `data/<instance>/persist`, and restart the container so startup creates the link. For a directory that is in use (such as agent session transcripts, where every new session creates a new file), copy it, verify the copy, then switch. For Claude Code sessions (needed by `/resume` and `--continue`), run inside the container after exiting Claude:

```bash
data=/var/lib/dev-container/data
mkdir -p "$data/home/.claude" &&
  cp -a ~/.claude/projects "$data/home/.claude/projects" &&
  diff -rq ~/.claude/projects "$data/home/.claude/projects" &&
  mv ~/.claude/projects ~/.claude/projects.premigration &&
  ln -s "$data/home/.claude/projects" ~/.claude/projects &&
  echo .claude/projects >> "$data/persist"
```

The `ln -s` links the running container immediately; a restart or recreation creates the same link. Delete `.premigration` once a rebuild confirms it works. omp sessions work the same way with `.omp/agent/sessions`. Codex sessions are not covered: `codex resume` also depends on versioned SQLite state files in `~/.codex`, and listing the whole of `~/.codex` would shadow the image's Codex package.

Links are only as durable as the application allows. If an application updates a listed file by atomically renaming a replacement over it, the link is lost and later writes remain only in the ephemeral home; list the containing directory instead when that is safe, and verify application behavior before relying on this for important state. Unlisted files—including shell history, caches, credentials, and runtime-installed tools—are discarded on container recreation. `data/` is excluded from both Git and the Docker build context, but it is still ordinary ignored machine data: commands such as `git clean -fdx` can permanently delete it.

Claude Code renames a new `~/.claude/.credentials.json` into place on token refreshes and logins, so a listed copy stops being linked and goes stale. Instead, run `claude setup-token` once (it requires a Claude subscription and prints a long-lived token), add `export CLAUDE_CODE_OAUTH_TOKEN=<token>` to `data/<instance>/home/.zshrc.local`, which the dotfiles `.zshrc` sources and Claude Code never rewrites, and list `.zshrc.local` in `data/<instance>/persist`.

Upgrading from the earlier layout, where every file under `data/home` was persisted and directories lived in `data/dirs`: before the next `./build`, seed the list while the old symlinks still exist, then review it:

```bash
(cd data/home && find . \( -type f -o -type l \) | sed 's|^\./||') > data/persist
```

Then, for each `data/home/<path>` symlink into `data/dirs`, remove the symlink and move `data/dirs/<path>` to `data/home/<path>`. Finally move `data/persist`, `data/home` and `data/certs` into `data/<instance>/` (copy them for each instance that should start with the same state), and run `./build <instance>` and `./start <instance>`: a running container keeps its old startup until it is recreated.

Upgrading from the old named home volume: copy each file you want to retain into its exact `data/<instance>/home` path and list it in `data/<instance>/persist` before running the new `./build`; the build removes the old container, though it does not delete the named volume. Also remove any obsolete `DOCKERFILE` setting and use `BUILD_TARGET=base` or `BUILD_TARGET=gui`. For example, run the following from the repository root while the old container is still running:

```bash
container=dev-container
container_home="$(docker exec "$container" sh -c 'printf %s "$HOME"')"
instance=work
mkdir -p "data/$instance/home/.config/tool"
docker cp "$container:$container_home/.config/tool/state.json" "data/$instance/home/.config/tool/state.json"
echo .config/tool/state.json >> "data/$instance/persist"
```

Inspect copied entries before rebuilding. Do not migrate a symlink unless its target will still exist after recreation; copy the underlying regular file instead when the old target lived only in the named home volume.

If the container was already rebuilt, the old Compose volume normally remains as `<instance>_home` (for example, `dev-container_home`). Locate it with `docker volume ls --filter name=_home`, then mount that exact volume read-only and copy only the files you intend to persist:

```bash
old=dev-container instance=work
mkdir -p "data/$instance/home/.config/tool"
docker run --rm \
  --mount "type=volume,src=${old}_home,dst=/old-home,readonly" \
  --mount "type=bind,src=$PWD/data/$instance/home,dst=/new-home" \
  ubuntu:24.04 sh -c 'mkdir -p /new-home/.config/tool && cp -a /old-home/.config/tool/state.json /new-home/.config/tool/state.json'
sudo chown -R "$(id -u):$(id -g)" "data/$instance/home/.config/tool"
echo .config/tool/state.json >> "data/$instance/persist"
```

Verify the copied files and the rebuilt container before optionally removing the old volume with `docker volume rm "${old}_home"`; that deletion is permanent. The obsolete `dev-container:latest` image can likewise be removed with `docker image rm dev-container:latest` after confirming no container still uses it.

### Docker access

The host Docker socket is not mounted by default, so `docker` commands inside the container fail with "Cannot connect to the Docker daemon". Set `DANGEROUSLY_MOUNT_DOCKER_SOCKET=true` in `config/<instance>/.env` to mount it; the scripts then add `docker-compose.docker-socket.yml` to the Compose files. The change applies when the container is recreated, so run `./build <instance>` and `./start <instance>`; `./start` refuses to continue while a running container's socket mount disagrees with the setting.

The socket is root-equivalent access to the host Docker daemon: anything in the container can start a container that bind-mounts any host path (on Docker Desktop, any shared path such as all of `/Users`), runs `--privileged`, or `docker exec`s into other instances. Leave it off for an instance that should be isolated from the host, other instances, or files outside its `CODE_DIR`.

### Docker-outside-of-docker bind mounts (macOS only)

This applies only when the host is **macOS**; on a Linux host it has no effect.

When the host Docker socket is mounted, `docker` commands inside the container run against the host's Docker daemon. On a Mac, Docker Desktop resolves bind-mount *sources* against the **macOS host** filesystem and only shares certain roots (e.g. `/Users`). But because of the Mac-only `/Users -> /home` symlink above, the repo's *real* path inside the container is `/home/$USERNAME/...`. Tools that canonicalize a path before mounting it — notably `cargo-prove prove build --docker` — then pass the unshared `/home/...` source, and Docker Desktop denies the mount (`path ... is not shared from the host`).

To fix this transparently, `scripts/docker-shim` is installed as `/usr/local/bin/docker` (which precedes the real `/usr/bin/docker` on `PATH`). It derives the container-path → host-path map from `/proc/self/mountinfo` and rewrites only bind-mount *sources* to the shared host path before exec'ing the real docker. On a Linux host there is no Docker Desktop and nothing to remap, so the shim is a transparent pass-through. It never touches container-target paths, named volumes, or non-mount arguments.

### Custom Mounts

To add extra mounts without modifying `docker-compose.yml`, copy `docker-compose.override.yml.example` to `config/<instance>/docker-compose.override.yml` and edit it. It applies only to that instance. Relative paths in it resolve against the repository root, not `config/<instance>/`.

```bash
cp docker-compose.override.yml.example config/work/docker-compose.override.yml
```

The scripts pass Compose its inputs explicitly (the instance `.env`, `docker-compose.yml`, the instance override, and the Docker socket file when enabled), so a root `.env` or `docker-compose.override.yml` is ignored and `COMPOSE_FILE` is rejected.

## Pre-installed Tools

See the [Dockerfile](Dockerfile) for the full list. Highlights:

- **Languages:** Go, Rust, Node.js, Python
- **Language servers:** gopls, rust-analyzer, typescript-language-server, pyright, solidity-language-server, bash-language-server
- **CLI:** git, gh, docker, gcloud, neovim, tmux, fzf, ripgrep, just, direnv, mise, glow, and others
- **Kubernetes & cloud:** kubectl, kubie, gke-gcloud-auth-plugin, gcx (Grafana CLI)
- **Blockchain:** Foundry (forge, cast, anvil, chisel)
- **AI:** Claude Code, OpenAI Codex

Codex is installed with OpenAI's standalone installer as the container user. The command is `~/.local/bin/codex`, its user-writable package is under `~/.codex/packages/standalone`, and `/etc/zsh/zshenv` exposes the command to interactive and non-interactive zsh sessions without changing npm's `/usr/local` global prefix. Individual Codex-adjacent files can coexist with that package when listed in `data/<instance>/persist`, but `auth.json` is not documented as safely persistable because no authenticated rewrite test proves Codex preserves its symlink.

## Custom CA Certificates

Place `.crt` files in `data/<instance>/certs/`. On every container start they are copied (regular files only) into the container's CA directory and installed with `update-ca-certificates`, so removing a file drops the certificate on the next restart. They are copied rather than mounted because the container can write `data/<instance>/`, and a nested bind mount of a path it controls could be redirected by a symlink when the container is recreated.

## GitHub token

The `./dev` script forwards a GitHub token into the container as `$GH_TOKEN` so `gh` and other tools work without a separate login inside the container.

By default it calls `gh auth token` on the host, which typically returns a broadly-scoped token. Prefer setting `GH_TOKEN` in `config/<instance>/.env` to a [fine-grained PAT](https://github.com/settings/personal-access-tokens/new) limited to just the repos and permissions you need. If `GH_TOKEN` is unset, `./dev` prints a warning and falls back to `gh auth token`.

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

SSH commit signing works via the forwarded SSH agent. Shells use the stable path `~/.ssh/agent.sock`. On each SSH connection and every 60 seconds, `ssh-agent-relink` checks whether its target contains the key matching `~/.ssh/id_ed25519.pub`, which startup writes from the first `SSH_AUTHORIZED_KEYS` entry. It preserves a matching agent and searches other forwarded sockets when the current agent is unreachable, empty, or holds different keys. If no agent has the expected key, it leaves the link unchanged and reports failure to its caller without printing into the SSH session. Keep at least one SSH connection open that forwards the expected key.

The host `./dev` launcher checks an existing agent before connecting. It loads keys into an empty agent, or starts an agent when the current one is unreachable, and refuses to connect if loading fails or leaves the agent empty. Changes to the container helper take effect after rebuilding and recreating the container; changing the host launcher takes effect on the next invocation.

Configure git in your dotfiles:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Run the agent regression tests with `python3 tests/ssh-agent-relink.py` and `python3 tests/dev-agent.py`. The relink tests create temporary keys and agents, including an actual signing probe; they leave the current session's agent untouched. For an isolated relink check, the helper accepts `ssh-agent-relink [stable-link [public-key-file]]`.

## Desktop agent control

The opt-in `gui` image includes system Python GI, AT-SPI, GTK 3/GDK capture, `xdotool`, `xprop`, and the existing `dbus-x11` session utilities. For example, BYOB's controller is documented in its `docs/desktop-testing.md`; run `just ui-doctor` in that checkout after GUI login. Controllers require access to the intended X11 display and AT-SPI session bus. The BYOB controller discovers the live display and session bus from the current desktop processes; do not persist session bus addresses or assume a display number. Check `org.a11y.Status.IsEnabled` and the selected application's actual controls; an absent browser bus variable does not explain accessibility by itself. An existing browser can still need `chrome://accessibility` overrides or pixel fallback. See the [GUI accessibility setup](#gui-access) above and BYOB's desktop guide for troubleshooting without resetting the current browser. The default `base` image remains SSH-only.
