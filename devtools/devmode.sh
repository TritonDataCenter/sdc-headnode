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

ROOT_DIR=$(cd $(dirname $0); pwd)
PKG_REPO="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/All"
BOOTSTRAP_TAR="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/bootstrap.tar"
GCC_RUNTIME="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/gcc452runtime.tgz"
PKGIN_FILE="http://pkgsrc.joyent.com/sdc/2010Q4/gcc45/All/pkgin-0.4.1.tgz"

if [[ "$(uname)" != "SunOS" ]] || [[ ! -f /etc/joyent_buildstamp ]]; then
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

if [[ ! -x /opt/local/sbin/pkg_add ]]; then
    echo "==> Installing minimal pkgsrc"
    (cd /opt && curl -k ${BOOTSTRAP_TAR} | gtar -C/ -xf -)
    (cd /opt && curl -k ${GCC_RUNTIME} | gtar -C/ -zxf -)
    echo "==> Installing pkgin"
    /opt/local/sbin/pkg_add ${PKGIN_FILE}
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
