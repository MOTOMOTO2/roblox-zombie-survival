#!/bin/bash
# Double-click this in Finder to pull the newest committed code. If the sync
# server is running in another window, Studio updates by itself a second later.
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "Node is not installed - see the README."
  read -r -p "Press return to close." _
  exit 1
fi

node tools/sync.js pull
echo
read -r -p "Press return to close." _
