#!/usr/bin/bash

TIMESTAMP=$1

if [[ -z $TIMESTAMP ]]; then
  echo "cannot create joysetupper script without a timestamp"
  exit 1
fi

echo "hey"

