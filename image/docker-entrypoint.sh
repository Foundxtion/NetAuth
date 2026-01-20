#!/bin/sh

to_lower()
{
    str="$1";
    lower=$(echo "$str" | tr 'QWERTYUIOPASDFGHJKLZXCVBNM' 'qwertyuiopasdfghjklzxcvbnm')

    echo "$lower"
}

create_dn()
{
    realm="$1";
    lower_realm=$(to_lower "$realm")
    dn=$(echo "$lower_realm" | sed "s/\./,dc=/")
    echo "dc=$dn"
}



create_global_var()
{
    export KADMIN_PASSWORD=${KADMIN_PASSWORD:-kadmin_password}
    export KDC_PASSWORD=${KDC_PASSWORD:-kdc_password}
    export KRB_MASTER_PASSWORD=${KRB_MASTER_PASSWORD:-master_password}
    export KRB_ADMIN_PASSWORD=${KRB_ADMIN_PASSWORD:-admin}
    
    export KRB_REALM=${KRB_REALM:-EXAMPLE.COM}
	export LDAP_REALM=$(to_lower "$KRB_REALM")
	export DOMAIN_NAME=${DOMAIN_NAME:-$(to_lower "$KRB_REALM")}
    export LDAP_DN=$(create_dn "$KRB_REALM")
    export LDAP_ORGANISATION=${LDAP_ORGANISATION:-EXAMPLE.COM}

    export LDAP_ADMIN_DN="cn=admin,${LDAP_DN}"
    export LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-admin}

    export LDAP_KDC_DN="uid=kdc,${LDAP_DN}"
    export LDAP_KADMIN_DN="uid=kadmin,${LDAP_DN}"

    export KRB_CONTAINER_DN="cn=krbContainer,${LDAP_DN}"
    export KRB5_KTNAME="/etc/krb5.keytab"
    export SSL_ENABLE=${SSL_ENABLE:-0}
}

replace_file()
{
    file="$1";

    sed -i "s/{{ LDAP_KDC_DN }}/${LDAP_KDC_DN}/g" "$file"
    sed -i "s/{{ LDAP_ADMIN_DN }}/${LDAP_ADMIN_DN}/g" "$file"
    sed -i "s/{{ LDAP_KADMIN_DN }}/${LDAP_KADMIN_DN}/g" "$file"
    sed -i "s/{{ LDAP_DN }}/${LDAP_DN}/g" "$file"
    sed -i "s/{{ KRB_CONTAINER_DN }}/${KRB_CONTAINER_DN}/g" "$file"
    sed -i "s/{{ LDAP_ORGANISATION }}/${LDAP_ORGANISATION}/g" "$file"
    sed -i "s/{{ KRB_REALM }}/${KRB_REALM}/g" "$file"
    sed -i "s/{{ DOMAIN_NAME }}/${DOMAIN_NAME}/g" "$file"
    sed -i "s/{{ LDAP_REALM }}/${LDAP_REALM}/g" "$file"
}


debug_echo() {
    echo "[DEBUG] --- $@";
}

slapd_listener() {
    if [ "$SSL_ENABLE" = "0" ]; then
        echo "ldapi:// ldap://";
    else
        echo "ldapi:// ldaps://";
    fi
}

stop_netauth() {
    pkill tail;
}

configuration() {
    for path in $(find /container/schemas -iname "0*"); do
        replace_file "$path";
    done
    replace_file "/container/config-slapd.sh";
    debug_echo "Launching configuration";
    /container/config-slapd.sh;
	mkdir -p /var/run/slapd && chown openldap:openldap /var/run/slapd;
    /usr/sbin/slapd -h "ldapi:// ldap://" -u openldap -g openldap;
    sleep 10;
    /container/config-openldap.sh
    /container/config-kerberos.sh

    pkill slapd;

    touch /var/lib/canary;
}

launch_app() {

    if [ "$SSL_ENABLE" = "1" ]; then
        find /certificates | xargs chown openldap:openldap
    fi

    debug_echo "Launching Bundle";
    debug_echo "Launching slapd";
    listener=$(slapd_listener;)
    /usr/sbin/slapd -h "$listener" -u openldap -g openldap -d 256 &
    sleep 5;
    debug_echo "Launching kadmind";
    /usr/sbin/kadmind -nofork &
    sleep 5;
    debug_echo "Launching kdc"
    /usr/sbin/krb5kdc -n &
    sleep 5;
    /usr/sbin/saslauthd -a kerberos5 -d &
    trap "stop_netauth" TERM INT;
}

ulimit -n 1024;
create_global_var;
debug_echo "realm: ${KRB_REALM}";
debug_echo "ldap dn: ${LDAP_DN}";
[ ! -e /var/lib/canary ] && configuration;
launch_app;

tail -f /dev/null
