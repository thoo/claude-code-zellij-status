#!/bin/bash

# Script to copy zjstatus config to Zellij layouts directory

set -e

echo "Ensuring Zellij layouts directory exists..."
mkdir -p "$HOME/.config/zellij/layouts"

echo "Copying default.kdl to $HOME/.config/zellij/layouts/default.kdl..."
cp default.kdl "$HOME/.config/zellij/layouts/default.kdl"

echo "Zellij layout updated successfully."
