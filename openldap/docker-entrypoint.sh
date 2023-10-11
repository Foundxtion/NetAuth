#!/bin/sh

COPY_SERVICE=${COPY_SERVICE:-0}

export COPY_SERVICE KRB5_REALM KRB5_KDC

/container/config.sh
chgrp openldap /var/run/saslauthd

if [ "$#" -ne 0  ]; then
    echo "$#";
    "$@";
    tail -f /dev/null;
fi

if [ "$COPY_SERVICE" = "1" ]; then
    exec /container/tool/run --copy-service --loglevel debug;
else
    exec /container/tool/run;
fi
