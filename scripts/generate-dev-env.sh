#!/usr/bin/env bash
# Unlock Vaultwarden CLI and generate .env for development

bw unlock --passwordenv BW_PASSWORD

cat <<EOF > .env
LIME_USERNAME=$(bw get username "pyreporter LIME_USERNAME")
LIME_PASSWORD=$(bw get password "pyreporter LIME_PASSWORD")
LIME_API_URL=$(bw get uri "pyreporter LIME_API_URL")
EOF

echo ".env created from Vaultwarden"