#!/usr/bin/env bash
set -e

# this script is not mean to be run here, it gets bundeled with the bundle scripts next to images

for f in *.zst; do
    echo "Loading $f..."
    zstd -dc "$f" | docker load
done
