#!/usr/bin/env bash
set -a
source "$(dirname "$0")/../../.env.relay"
set +a
exec ./notify_relay
