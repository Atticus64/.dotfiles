map=$(setxkbmap -print | awk -F"+" '/xkb_symbols/ {print $2}')


if [ "$map" == "us" ]; then
	setxkbmap es
elif [ "$map" == "es" ]; then
	setxkbmap us
fi

