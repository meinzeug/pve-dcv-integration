# Thinclient startup is handled by dedicated systemd services.
# Disable live-config's generic tty/startx profile hook so it does not
# interfere with SSH logins or alternate virtual consoles.
return 0 2>/dev/null || exit 0
