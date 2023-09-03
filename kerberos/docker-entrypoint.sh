#!/bin/sh

KADMIN_LAUNCH=${KADMIN_LAUNCH:-0}

KRB5_MASTER_PASSWORD="${KRB5_MASTER_PASSWORD:-admin_krb}"
LDAP_DN="${LDAP_DN:-"dc=example,dc=org"}"
LDAP_KRB5_CONTAINER_DN="${LDAP_KRB5_CONTAINER_DN:-"cn=krbContainer,"$LDAP_DN}"
LDAP_KRB5_REALM_DN="cn=$KRB5_REALM,${LDAP_KRB5_CONTAINER_DN}"

LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-"cn=admin,"$LDAP_DN}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-admin}"

LDAP_KDC_DN="${LDAP_KDC_DN:-"cn=admin,"$LDAP_DN}"
LDAP_KDC_PASSWORD="${LDAP_KDC_PASSWORD:-admin}"

LDAP_URI="${LDAP_URI:-ldap://ldap_example_ip/}"
LDAP_SETUP="${LDAP_SETUP:-1}"

pass_stash=/var/lib/krb5kdc/admin.stash

if [ -z "${KRB5_REALM}" ]; then
    echo "No KRB5_REALM Provided. Exiting ..."
    exit 1
fi

if [ -z "${KRB5_KDC}" ]; then
    echo "No KRB5_KDC Provided. Exiting ..."
    exit 1
fi

if [ -z "${KRB5_ADMINSERVER}" ]; then
    echo "KRB5_ADMINSERVER provided. Using ${KRB5_KDC} instead."
    KRB5_ADMINSERVER=${KRB5_KDC}
fi

is_ldap_setup()
{
    ldapsearch -x -LLL -H "$LDAP_URI" -D "$LDAP_ADMIN_DN" \
        -w "$LDAP_ADMIN_PASSWORD" -b "$LDAP_KRB5_REALM_DN" \
        2>/dev/null >/dev/null
}

is_ldap_up()
{
    if [ "$LDAP_SETUP" = "1" ]; then
        ldapwhoami -x -H "$LDAP_URI" -D "$LDAP_ADMIN_DN" \
            -w "$LDAP_ADMIN_PASSWORD" 2>/dev/null >/dev/null
    else
        is_ldap_setup
    fi
}

wait_for_ldap()
{
    echo "Waiting for LDAP..."
    wait_err=0
    max_wait_err=15

    while [ "$wait_err" -lt "$max_wait_err" ]; do
        if is_ldap_up; then
            sleep 2
            return
        fi
        max_wait_err=$((wait_err + 1))
        sleep 1
    done

    echo "LDAP still not up, aborting..."
    exit 1
}

retry_ldap()
{
    max_ldap_err=3
    ldap_err=${ldap_err:-0}
    while true; do
        if [ -f input_file ]; then
            "$@" < input_file
        else
            "$@"
        fi

        if [ "$?" -eq 0 ]; then
            return
        fi

        if [ "$ldap_err" -ge "$max_ldap_err" ]; then
            break
        fi

        echo "ldap comand has failed, retrying..."
        sleep 3
        ldap_err=$((ldap_err + 1))
        is_ldap_up
    done

    echo "LDAP error aborting..." >&2
    exit 1
}

setup_stash()
{
    dn="$1"
    password="$2"

    cat > input_file << EOF
$password
$password
EOF

    retry_ldap kdb5_ldap_util -D "$dn" -w "$password" \
        stashsrvpw -f "$pass_stash" "$dn"
    rm -f input_file
}

wait_for_ldap
if is_ldap_setup && [ "$LDAP_SETUP" = "1" ]; then
    echo "LDAP is already setup!"
    echo "Setting LDAP_SETUP back to 0"
    LDAP_SETUP=0
fi


echo "Creating Krb5 Client Configuration"

cat <<EOT > /etc/krb5.conf
[libdefaults]
    dns_lookup_realm = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = true
    default_realm = ${KRB5_REALM}

 [realms]
     ${KRB5_REALM} = {
        kdc = ${KRB5_KDC}
        admin_server = ${KRB5_ADMINSERVER}
     }
EOT

if [ ! -f "$pass_stash" ]; then
    echo "Creating KDC Configuration"
cat <<EOT > /var/lib/krb5kdc/kdc.conf
[kdcdefaults]
    kdc_listen = 88
    kdc_tcp_listen = 88

[realms]
    ${KRB5_REALM} = {
        kadmin_port = 749
        max_life = 12h 0m 0s
        max_renewable_life = 2d 0h 0m 0s
        master_key_type = aes256-cts
        supported_enctypes = aes256-cts:normal aes128-cts:normal
        default_principal_flags = +preauth
        database_module = LDAP
    }

[dbdefaults]
    ldap_kerberos_container_dn = $LDAP_KRB5_CONTAINER_DN

[dbmodules]
    LDAP = {
        db_library = kldap
        ldap_kdc_dn = "$LDAP_KDC_DN"
        ldap_kadmind_dn = "$LDAP_ADMIN_DN"
        ldap_service_password_file = $pass_stash
        ldap_servers = $LDAP_URI
        ldap_conns_per_server = 5
    }

[logging]
    kdc = STDERR
    admin_server = STDERR
    default = STDERR
EOT

    echo "Creating Default Policy - Admin Access to */admin"
    echo "*/admin@${KRB5_REALM} *" > /var/lib/krb5kdc/kadm5.acl
    echo "*/service@${KRB5_REALM} aci" >> /var/lib/krb5kdc/kadm5.acl

    if [ -z "${KRB5_MASTER_PASSWORD}" ]; then
        echo "No Password for krb master provided ... Creating One"
        KRB5_MASTER_PASSWORD="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c"${1:-32}";echo;)"
        echo "Using Password ${KRB5_MASTER_PASSWORD}"
    fi

    if [ "$LDAP_SETUP" = "1" ]; then
        echo "Setup LDAP DN"
        retry_ldap kdb5_ldap_util -D "$LDAP_ADMIN_DN" \
            -w "$LDAP_ADMIN_PASSWORD" create -subtrees "$LDAP_DN" -s -r "$KRB5_REALM" \
            -H "$LDAP_URI" -P "$KRB5_MASTER_PASSWORD"
    fi

    echo "Creating admin.stash"

    setup_stash "$LDAP_ADMIN_DN" "$LDAP_ADMIN_PASSWORD"
    if [ "$LDAP_ADMIN_DN" != "$LDAP_KDC_DN" ]; then
        setup_stash "$LDAP_KDC_DN" "$LDAP_KDC_PASSWORD"
    fi

    if [ "$LDAP_SETUP" = "1" ]; then
        if [ -z "${KRB5_ADMIN_PASSWORD}" ]; then
            echo "No Password for kdb provided ... Creating One"
            KRB5_ADMIN_PASSWORD="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c"${1:-32}";echo;)"
            echo "Using Password ${KRB5_ADMIN_PASSWORD}"
        fi

        echo "Creating Admin Account"
        kadmin.local -q "addprinc -pw ${KRB5_ADMIN_PASSWORD} admin/admin@${KRB5_REALM}"
        rm -rf input_file

    fi

    echo "stashing master password"
    kdb5_util stash -P "$KRB5_MASTER_PASSWORD"
fi

if [ "$#" -eq 0 ]; then
    if [ "$KADMIN_LAUNCH" -eq 1 ]; then
        set -- /usr/sbin/kadmind -nofork
    else
        set -- /usr/sbin/krb5kdc -n
    fi
fi

exec "$@"
