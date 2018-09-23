#!/usr/bin/env bash

set -x;

rm -rf ${bamboo.working.directory}/.git ${bamboo.working.directory}/.ssh;

tar -I "zstd -10" -cvf /tmp/sources.tar.zst -C ${bamboo.working.directory} . && mv /tmp/sources.tar.zst ${bamboo.working.directory}/sources.tar.zst