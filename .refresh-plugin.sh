#!/bin/bash

# Refresh cc-zjstatus plugin from local marketplace

set -e

echo "Removing cc-zjstatus plugin..."
claude plugin uninstall cc-zjstatus || true

echo "Updating marketplace..."
claude plugin marketplace update claude-code-zellij-status

echo "Adding cc-zjstatus plugin..."
claude plugin install cc-zjstatus

echo "Updating Zellij layout..."
mkdir -p "$HOME/.config/zellij/layouts"
cp default.kdl "$HOME/.config/zellij/layouts/default.kdl"

echo "Done! Plugin refreshed."
