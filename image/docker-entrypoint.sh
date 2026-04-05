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
	export DOMAIN_NAME=$(hostname --fqdn)
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

initialization() {
	mkdir -p /netauth;
    for path in $(find /container/schemas -type f -iname "0*"); do
        replace_file "$path";
    done
    for path in $(find /container/config-templates -type f); do
        replace_file "$path";
		cp "$path" "/netauth/$(basename "$path")";
    done

    replace_file "/container/init-slapd.sh";
    debug_echo "Launching initialization";
    /container/init-slapd.sh;
	create_symbol_links "init";
    /usr/sbin/slapd -F /etc/ldap/slapd.d -h "ldapi:// ldap://" -u openldap -g openldap;
    sleep 10;
    /container/init-openldap.sh
    /container/init-kerberos.sh

    pkill slapd;

    touch /var/lib/canary;
}

create_symbol_links() {
	mkdir /var/lib/ldap
	mkdir -p /etc/sasl2/ /var/run/slapd && chown openldap:openldap /var/run/slapd;
	ln -s -f /netauth/krb5.conf /etc/krb5.conf
	ln -s -f /netauth/kdc.conf /etc/krb5kdc/kdc.conf
	ln -s -f /netauth/kadm5.acl /etc/krb5kdc/kadm5.acl
	ln -s -f /netauth/service.keyfile /etc/krb5kdc/service.keyfile
	ln -s -f /netauth/krb5.keytab /etc/krb5.keytab
	ln -s -f /netauth/slapd.conf /usr/lib/sasl2/slapd.conf
	ln -s -f /netauth/slapd.conf /etc/sasl2/slapd.conf

	if [ "$1" = "init" ]; then
		mkdir -p /netauth/lib;
		mv /var/lib/ldap /netauth/lib;
		mv /etc/ldap/slapd.d /netauth/slapd.d;
		mv /etc/default/slapd /netauth/slapd;
	fi
	ln -s -f /netauth/ldap.conf /etc/ldap/ldap.conf
	ln -s -f /netauth/slapd /etc/default/slapd
	ln -s -f /netauth/lib/ldap /var/lib/ldap
	ln -s -f /netauth/slapd.d /etc/ldap/slapd.d
	chown -R openldap:openldap /netauth/lib;
	chown -R openldap:openldap /netauth/slapd.d;
	chown -R openldap:openldap /var/lib/ldap;
	chown -R openldap:openldap /etc/ldap/ldap.conf;
	chown -R openldap:openldap /etc/ldap/slapd.d;
	chown -R openldap:openldap /var/lib/ldap;
	chown -R openldap:openldap /etc/default/slapd;
}

launch_app() {

    if [ "$SSL_ENABLE" = "1" ]; then
        find /certificates | xargs chown openldap:openldap
    fi

    debug_echo "Launching Bundle";
    debug_echo "Launching slapd";
    listener=$(slapd_listener;)
    /usr/sbin/slapd -F /etc/ldap/slapd.d -h "$listener" -u openldap -g openldap -d 256 &
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
if [ ! -e /var/lib/canary ]; then
	initialization;
	launch_app;
else
	create_symbol_links;
	launch_app;
fi

tail -f /dev/null
