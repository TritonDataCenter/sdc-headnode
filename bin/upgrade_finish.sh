#!/bin/bash

BASH_XTRACEFD=4
set -o xtrace

if [[ $1 == "pre" ]]; then
    echo "Upgrade pre-setup tasks"
fi

if [[ $1 == "post" ]]; then
    echo "Upgrade post-setup tasks"
    mv /var/upgrade_headnode /var/upgrade.$(date -u "+%Y%m%dT%H%M%S")
fi
