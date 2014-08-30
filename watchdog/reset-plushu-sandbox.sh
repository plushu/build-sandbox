#! /usr/bin/env bash

DOMAIN=sandbox.plushu.org
SSH_IDENTITY_FILE="$HOME/keys/ssh/$DOMAIN/id_rsa"
TOKEN=$(<"$HOME/tokens/digitalocean/plushu-sandbox-reimaging")
DROPLET_ID=$(<"$HOME/.config/reset-plushu-sandbox/DROPLET_ID")
RESTORE_IMAGE_ID=$(<"$HOME/.config/reset-plushu-sandbox/RESTORE_IMAGE_ID")

if [[ -f "$SSH_IDENTITY_FILE" ]]; then
  timeout 5 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
    -i "$SSH_IDENTITY_FILE" "root@$DOMAIN" \
    -- 'echo "The system is going down for reset NOW!" | wall'
fi

curl -X POST "https://api.digitalocean.com/v2/droplets/$DROPLET_ID/actions" \
  -d'{"type":"restore","image":"'"$RESTORE_IMAGE_ID"'"}' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
