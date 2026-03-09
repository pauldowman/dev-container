#!/bin/bash
set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <username> <code_path>"
  echo "  username:  the user to create inside the container"
  echo "  code_path: the absolute path to mount as the code directory"
  exit 1
fi

USERNAME=$1 CODE_PATH=$2 docker compose build
