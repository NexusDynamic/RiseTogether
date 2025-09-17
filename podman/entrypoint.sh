#!/bin/bash
sudo rm -f /tmp/.X0-lock
sudo Xvfb :0 -ac -screen 0 "1x1x24" +extension GLX +render -noreset -nolisten tcp  &
XVFB_PROC=$!
sleep 1
export DISPLAY=:0
sudo service dbus start
# just write a dummy config to make sure dconf doesn't complain
dconf write /org/gnome/desktop/input-sources/xkb-options "['caps:none']"
# execute flutter with arguments
export RISETOGETHER_CONFIG=$(cat ./risetogether_config.json)
RISETOGETHER_CONFIG=$RISETOGETHER_CONFIG flutter --no-version-check -dlinux run --dart-define=APP_MODE=headless_server --no-pub "$@"
flutter  
kill $XVFB_PROC
exit
