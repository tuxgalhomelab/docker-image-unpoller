#!/usr/bin/env bash
set -E -e -o pipefail

unpoller_config="/data/unpoller/config/unpoller.conf"

set_umask() {
    # Configure umask to allow write permissions for the group by default
    # in addition to the owner.
    umask 0002
}

start_unpoller() {
    echo "Starting Unpoller ..."
    echo

    exec unpoller --config "${unpoller_config:?}"
}

set_umask
start_unpoller
