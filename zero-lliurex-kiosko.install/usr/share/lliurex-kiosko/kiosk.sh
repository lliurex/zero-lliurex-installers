#!/bin/bash

xset -dpms
xset s off

compiz &

start-pulseaudio-x11

feh --bg-scale /usr/share/backgrounds/lliurex-desktop-15.png

while true; do
    req_install=`type -fp chromium-browser` || zenity --warning --text "chromium-browser is not installed, this session don't meet the required binaries to run properly"
    if [ "x$req_install" == "x" ];then
	zenity --warning --text "Exiting now"
	exit 1
    fi
    touch /tmp/kiosk.mode
    rm -rf /home/kiosk/.{config,cache}/chromium
    mkdir -p /home/kiosk/.config/chromium
    tar xvfz /usr/share/lliurex-kiosko/chromium_config.tgz -C /home/kiosk/.config/chromium
    xmodmap -e "pointer = 1 2 99"
    xmodmap -e "keycode 67 = Alt_L"
    chromium-browser --kiosk --no-first-run --disable-infobars --disable-translate --disable-session-crashed-bubble  'http://www.cece.gva.es'
    find /home/kiosk -maxdepth 1 -mindepth 1 -not -name .config -and -not -iname Descargas -and -not -iname .gvfs -and -not -iname Downloads -exec rm -rf {} \;
    sleep 1
done


