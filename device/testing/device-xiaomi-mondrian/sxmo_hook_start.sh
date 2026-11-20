#!/bin/sh

/usr/share/sxmo/default_hooks/sxmo_hook_start.sh

if [ "$SXMO_WM" = river ]; then
	wlr-randr --output DSI-1 --scale 3
fi
