#!/bin/sh
#
# Build redis tarball for zones/redis/redis-$VERSION.tar.bz2
# Run this on smartos.
#

set -e

if [[ `uname` != "SunOS" ]]; then
    echo "error: $0: must be run on SmartOS"
    exit 1
fi

wget http://redis.googlecode.com/files/redis-2.4.1.tar.gz
gtar xf redis-2.4.1.tar.gz
cd redis-2.4.1
gcc --version     # gcc (GCC) 4.5.2
make
rm -rf redis
mkdir -p redis/bin redis/share redis/etc
find src -perm /u+x -name "redis-*" | xargs -I{} cp {} redis/bin
cp redis.conf redis/share/redis.conf.sample
tar cjf redis-2.4.1.tar.bz2 redis

