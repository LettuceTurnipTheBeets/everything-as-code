#!/usr/bin/env bash

set -x;

if [ ! -z "${bamboo.hipchat_channel}" ]
then
  if [ ! -f tracking.tmp ]
  then
    curl -d '{\"color\":\"green\",\"message\":\"${bamboo.deploy.project} deployment of ${bamboo.deploy.release} to ${bamboo.deploy.environment} done successfully.\",\"notify\":true,\"message_format\":\"text\"}' -H 'Content-Type: application/json' https://my-hipchat-server.example.com/v2/room/${bamboo.hipchat_channel}/notification?auth_token=${bamboo.hipchat_token}
  else
    curl -d '{\"color\":\"red\",\"message\":\"${bamboo.deploy.project} deployment of ${bamboo.deploy.release} to ${bamboo.deploy.environment} failed.\",\"notify\":true,\"message_format\":\"text\"}' -H 'Content-Type: application/json' https://my-hipchat-server.example.com/v2/room/${bamboo.hipchat_channel}/notification?auth_token=${bamboo.hipchat_token}
  fi
fi