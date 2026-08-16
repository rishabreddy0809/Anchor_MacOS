#!/bin/zsh
# Live Google Classroom sync trace.
#
#   Terminal 1:  ./watch-classroom.sh
#   Terminal 2:  open ~/Library/Developer/Xcode/DerivedData/Anchor-*/Build/Products/Debug/Anchor.app
#
# Quit any running Anchor first, or the launch is a no-op and you see nothing.
echo "Watching Classroom sync — Ctrl-C to stop. Launch Anchor now."
/usr/bin/log stream \
  --predicate '(subsystem == "com.anchor.google") OR (subsystem == "com.anchor.diag")' \
  --level debug --style compact
