#!/bin/sh

debug_echo()
{
    echo "[DEBUG] --- $@";
}

set_ldap_pwd() 
{
    dn="$1";
    password="$2";

    debug_echo "Setting up LDAP password for $dn"

    cat > input_file <<-EOF
$password
$password
EOF

    ldappasswd -x -D ${LDAP_ADMIN_DN} -w "${LDAP_ADMIN_PASSWORD}" -S "$dn" < input_file
    rm -f input_file
    echo "";
}

set_ldap_admin_pwd()
{
    ldif_file="/container/schemas/modify/00-admin_change_password.ldif"
    cat > input_file <<-EOF
$LDAP_ADMIN_PASSWORD
$LDAP_ADMIN_PASSWORD
EOF

    hash=$(slappasswd < input_file)
    hash=$(echo "$hash" | sed "s~/~\\\/~g")

    sed -i "s/{{ HASH }}/${hash}/g" "$ldif_file"
    ldapmodify -H ldapi:// -Y EXTERNAL -f "$ldif_file"

    ldappasswd -x -D ${LDAP_ADMIN_DN} -w "admin" -S < input_file

    rm -f input_file
    echo "";
}

create_slapd_conf()
{
    cat > /usr/lib/sasl2/slapd.conf <<-EOF
keytab: /etc/krb5.keytab
sasl-host: ${DOMAIN_NAME}
pwcheck_method: saslauthd
saslauthd_path: /var/run/saslauthd/mux
EOF
    adduser openldap sasl;
}

create_slapd_conf;
debug_echo "Check config tree after initial installation:"
ldapsearch -LLLQ -Y EXTERNAL -H ldapi:/// -b cn=config dn
debug_echo "Check done"

debug_echo "Delete default admin password and replace with new one"
set_ldap_admin_pwd;

debug_echo "Install kerberos schema"
zcat /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz | ldapadd -Q -Y EXTERNAL -H ldapi:///

debug_echo "Change index for kerberos dn"
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /container/schemas/modify/01-kerberos_index.ldif

debug_echo "Add kadmin and kdc accounts"
ldapadd -x -D ${LDAP_ADMIN_DN} -w "${LDAP_ADMIN_PASSWORD}" -f /container/schemas/add/02-kerberos_accounts.ldif

set_ldap_pwd "${LDAP_KADMIN_DN}" "${KADMIN_PASSWORD}"
set_ldap_pwd "${LDAP_KDC_DN}" "${KDC_PASSWORD}"

debug_echo "Change access rules for kerberos accounts"
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /container/schemas/modify/03-kerberos_access.ldif

echo "SASL_MECH GSSAPI" >> /etc/ldap/ldap.conf
echo "SASL_REALM ${KRB_REALM}" >> /etc/ldap/ldap.conf
echo "SASL_NOCANON on" >> /etc/ldap/ldap.conf

debug_echo "Changing olcAuthzRegexp"
ldapmodify -H ldapi:/// -Y EXTERNAL -f /container/schemas/modify/04-auth-regexp.ldif

debug_echo "Added SASL rules"
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /container/schemas/modify/05-sasl.ldif

debug_echo "Added LDAP groups"
ldapadd -x -D ${LDAP_ADMIN_DN} -w "${LDAP_ADMIN_PASSWORD}" -f /container/schemas/add/06-ldap_groups.ldif

if [ "$SSL_ENABLE" = "1" ]; then
    debug_echo "Configure ssl connection";
    debug_echo "set access available to certificates";
    find /certificates | xargs chown openldap:openldap
    debug_echo "Added ssl configuration to ldap";
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /container/schemas/modify/07-ssl_add.ldif
    debug_echo "Added certificates to ldap";
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /container/schemas/modify/08-certificates_add.ldif
fi
