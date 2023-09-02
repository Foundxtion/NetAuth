#!/bin/sh

COPY_SERVICE=${COPY_SERVICE:-0}

/container/config.sh

[ "$#" -ne 0  ] && exec "$@"

if [ "$COPY_SERVICE" = "1" ]; then
    exec /container/tool/run --copy-service --loglevel debug;
else
    exec /container/tool/run;
fi
