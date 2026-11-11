#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/common.sh"
require_root
require_ns v

ip netns exec v curl -v --max-time 8 "http://$G_IP:8080/"
