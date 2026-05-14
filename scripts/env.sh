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
