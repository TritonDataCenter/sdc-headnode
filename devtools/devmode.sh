#!/bin/bash
#
# Copyright (c) 2010 Joyent Inc., All Rights Reserved.
#
# This is intended to provide pkgsrc for a live image GZ when needed for
# development purposes.  It also mounts /opt/root as /root providing developers
# a quick way to keep stuff in /root across reboots.  (just rerun this script
# after each boot).
#
# WARNINGS:
#
# DO NOT USE IN PRODUCTION.
# DO NOT USE UNLESS YOU NEED IT AND DO NOT WRITE SOFTWARE THAT DEPENDS ON THIS.
#

#export PS4='${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -o xtrace
set -o errexit
set -o pipefail

ROOT_DIR=$(cd $(dirname $0); pwd)
PKG_REPO="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/All"
BOOTSTRAP_TGZ="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/bootstrap.tar.gz"
GCC_RUNTIME="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/gcc452runtime.tgz"

if [[ "$(uname)" != "SunOS" ]] || [[ "$(uname -v | cut -d'_' -f1)" != "joyent" ]]; then
    echo "FATAL: this only works on the SmartOS Live Image!"
    exit 1 
fi

if [[ $(wc -c /etc/resolv.conf | awk '{ print $1 }') -eq 0 ]]; then
    echo "==> Setting up resolver"
    cat >/etc/resolv.conf <<EOF
search joyent.us
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
fi

if [[ -z $(grep "hosts.* dns" /etc/nsswitch.conf) ]]; then
    echo "==> Adding DNS to nsswitch.conf"
    sed -e "s/^hosts:.*$/hosts:      files mdns dns/" /etc/nsswitch.conf > /tmp/nsswitch.conf.new \
        && cp /tmp/nsswitch.conf.new /etc/nsswitch.conf
fi

if [[ ! -x /opt/local/bin/pkgin ]]; then
    echo "==> Installing minimal pkgsrc"
    (cd /opt && curl -k ${BOOTSTRAP_TGZ} | gtar -C/ -zxf -)
    (cd /opt && curl -k ${GCC_RUNTIME} | gtar -C/ -zxf -)
    echo "PKG_PATH=${PKG_REPO}" >> \
      /opt/local/etc/pkg_install.conf
    echo "==> Installing pkgin"
    mkdir -p /opt/local/etc/pkgin
    echo ${PKG_REPO} > /opt/local/etc/pkgin/repositories.conf
    /opt/local/bin/pkgin update
fi

if [[ -z $(crle | grep '/opt/gcc/lib') ]]; then
    echo "==> Setting up crle"
    crle -u -l /opt/gcc/lib
    crle -u -l /opt/local/lib
fi

if [[ -z $(mount | grep "^/root") ]]; then
    echo "==> Setting up persistent /root"
    if [[ ! -d /opt/root ]]; then
        cp -rP /root /opt/root
    fi
    mount -O -F lofs /opt/root /root
fi

exit 0
