#!/bin/sh
# Quit a browser if it runs, then start it with the locally built DevTools frontend.
# Usage: launch-browser.sh <application name>
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <application name>" >&2
  exit 1
fi
app=$1

repo_dir=$(cd "$(/usr/bin/dirname "$0")" && /bin/pwd)
frontend_dir="$repo_dir/devtools/devtools-frontend/out/Default/gen/front_end"

if [ ! -f "$frontend_dir/devtools_app.html" ]; then
  echo "No DevTools build at $frontend_dir. Run: cd $repo_dir/devtools/devtools-frontend && autoninja -C out/Default" >&2
  exit 1
fi

if /usr/bin/pgrep -xq "$app"; then
  /usr/bin/osascript -e "tell application \"$app\" to quit"
  tries=0
  while /usr/bin/pgrep -xq "$app"; do
    tries=$((tries + 1))
    if [ "$tries" -gt 20 ]; then
      echo "$app did not quit within 10 seconds. Quit it, then run this script again." >&2
      exit 1
    fi
    /bin/sleep 0.5
  done
fi

# Percent-encode each path segment so the file URL stays valid for any path.
frontend_url=$(/usr/bin/osascript -l JavaScript \
  -e 'function run(argv) { return argv[0].split("/").map(encodeURIComponent).join("/"); }' "$frontend_dir")

/usr/bin/open -a "$app" --args --custom-devtools-frontend="file://$frontend_url"
