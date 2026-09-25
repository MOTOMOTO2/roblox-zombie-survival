#!/bin/bash
# Double-click this in Finder on a Mac to start the Rojo sync server.
# Everything it needs is fetched into .tools/ on first run; nothing is
# installed system-wide. Close the Terminal window (or press Ctrl+C) to stop.
cd "$(dirname "$0")" || exit 1

if ! command -v node >/dev/null 2>&1; then
  echo "Node is not installed."
  echo "Install the LTS build from https://nodejs.org (or: brew install node), then run this again."
  echo
  read -r -p "Press return to close." _
  exit 1
fi

# First run only: fetch the pinned Rojo CLI and put the plugin in Studio.
if [ ! -x .tools/bin/rojo ] && ! command -v rojo >/dev/null 2>&1; then
  echo "First run - setting up Rojo. This takes a few seconds."
  node tools/sync.js install || exit 1
  node tools/sync.js plugin || exit 1
  echo
  echo "The Rojo plugin was installed. If Studio is already open, quit and reopen it."
  echo
fi

node tools/sync.js serve
status=$?
echo
echo "Sync server stopped."
[ $status -ne 0 ] && read -r -p "Press return to close." _
exit $status
