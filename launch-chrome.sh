#!/bin/sh
# Quit Google Chrome if it runs, then start it with the locally built DevTools frontend.
exec "$(/usr/bin/dirname "$0")/launch-browser.sh" "Google Chrome"
