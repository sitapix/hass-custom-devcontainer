#!/bin/bash

echo "================"
echo "To test run:"
echo "$ sudo container setup-dev"
echo "$ sudo container launch"
echo ""
echo "You may need to run the seccond command two or more times for all packages to install"
echo "================"

docker run --rm -it \
    -p 5002:8123 \
    -v $(pwd):/workspaces/test \
    -v $(pwd):/config/www/workspace \
    -e LOVELACE_PLUGINS="thomasloven/lovelace-card-mod thomasloven/lovelace-auto-entities custom-cards/button-card kalkih/mini-media-player" \
    -e ENV_FILE="/workspaces/test/test.env" \
    thomasloven/hass-custom-devcontainer bash
    # sudo container setup-dev
    # sudo container launch