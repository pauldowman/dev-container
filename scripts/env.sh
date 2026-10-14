load_env_file() {
  local env_file="$1"

  if [[ ! -f "$env_file" ]]; then
    return
  fi

  local restore_allexport=false
  case "$-" in
    *a*) ;;
    *)
      set -a
      restore_allexport=true
      ;;
  esac

  # shellcheck source=/dev/null
  source "$env_file"

  if [[ "$restore_allexport" == "true" ]]; then
    set +a
  fi
}

# Sets INSTANCE and INSTANCE_CONFIG_DIR and loads config/<instance>/.env;
# expects SCRIPT_DIR to be the repository root.
select_instance() {
  INSTANCE="$1"

  if [[ ! "$INSTANCE" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Error: instance must start with a lowercase letter or digit and contain only lowercase letters, digits, underscores, or hyphens" >&2
    exit 1
  fi
  if (( ${#INSTANCE} > 123 )); then
    echo "Error: instance must be at most 123 characters" >&2
    exit 1
  fi

  INSTANCE_CONFIG_DIR="$SCRIPT_DIR/config/$INSTANCE"
  if [[ ! -f "$INSTANCE_CONFIG_DIR/.env" ]]; then
    echo "Error: instance '$INSTANCE' has no configuration; create $INSTANCE_CONFIG_DIR/.env" >&2
    exit 1
  fi

  load_env_file "$INSTANCE_CONFIG_DIR/.env"
  INSTANCE="$1"

  if [[ -n "${COMPOSE_FILE+x}" ]]; then
    echo "Error: COMPOSE_FILE is not supported; put extra Compose settings in $INSTANCE_CONFIG_DIR/docker-compose.override.yml" >&2
    exit 1
  fi

  case "${DANGEROUSLY_MOUNT_DOCKER_SOCKET:-false}" in
    true|false) ;;
    *)
      echo "Error: DANGEROUSLY_MOUNT_DOCKER_SOCKET must be true or false" >&2
      exit 1
      ;;
  esac

  export INSTANCE
}

# Compose would otherwise auto-load a root .env and docker-compose.override.yml,
# so every Compose call names its inputs explicitly.
set_compose_args() {
  mkdir -p "$INSTANCE_CONFIG_DIR/install"

  COMPOSE_ARGS=(-p "$INSTANCE" --env-file "$INSTANCE_CONFIG_DIR/.env" -f "$SCRIPT_DIR/docker-compose.yml")
  if [[ -f "$INSTANCE_CONFIG_DIR/docker-compose.override.yml" ]]; then
    COMPOSE_ARGS+=(-f "$INSTANCE_CONFIG_DIR/docker-compose.override.yml")
  fi
  if [[ "${DANGEROUSLY_MOUNT_DOCKER_SOCKET:-false}" == "true" ]]; then
    COMPOSE_ARGS+=(-f "$SCRIPT_DIR/docker-compose.docker-socket.yml")
  fi
}
