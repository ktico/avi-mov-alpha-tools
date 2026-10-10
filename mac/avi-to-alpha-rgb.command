#!/bin/bash
set -eu
COMMAND_DIR=$(cd "$(dirname "$0")" && pwd)
exec /bin/bash "$COMMAND_DIR/mov-to-alpha-rgb.command" --input-kind avi "$@"
