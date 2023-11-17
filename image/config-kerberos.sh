#!/bin/sh

debug_echo()
{
    echo "[DEBUG] --- $@";
}

setup_stash()
{
    dn="$1";
    password="$2";

    debug_echo "Setting up kerberos password for $dn"

    cat > input_file <<-EOF
$password
$password
EOF
    debug_echo "Content of input_file:"
    cat -ne input_file
    
    kdb5_ldap_util -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" stashsrvpw -f /etc/krb5kdc/service.keyfile "$dn" < input_file
    rm -f input_file
}

debug_echo "Creating krb5.conf"
cat > /etc/krb5.conf <<-EOF
[libdefaults]
        default_realm = ${KRB_REALM}
        dns_lookup_realm = false
        dns_lookup_kdc = false
        ticket_lifetime = 24h
        forwardable = true
        proxiable = true
        rdns = false

[realms]
        ${KRB_REALM} = {
                kdc = ${DOMAIN_NAME}
                admin_server = ${DOMAIN_NAME}
                default_domain = ${DOMAIN_NAME}
        }
EOF

debug_echo "Creating kdc.conf"
cat > /etc/krb5kdc/kdc.conf <<-EOF
[realms]
        ${KRB_REALM} = {
                database_module = openldap_ldapconf
                max_life = 12h 0m 0s
                max_renewable_life = 2d 0h 0m 0s
                master_key_type = aes256-cts
                supported_enctypes = aes256-cts:normal aes128-cts:normal
                default_principal_flags = +preauth
        }

[dbmodules]
        openldap_ldapconf = {
                db_library = kldap

                ldap_kerberos_container_dn = ${KRB_CONTAINER_DN}
                # if either of these is false, then the ldap_kdc_dn needs to
                # have write access as explained above
                disable_last_success = true
                disable_lockout = true
                ldap_conns_per_server = 5
                ldap_servers = ldapi:///

                # this object needs to have read rights on
                # the realm container, principal container and realm sub-trees
                ldap_kdc_dn = "${LDAP_KDC_DN}"

                # this object needs to have read and write rights on
                # the realm container, principal container and realm sub-trees
                ldap_kadmind_dn = "${LDAP_KADMIN_DN}"

                # this file will be used to store plaintext passwords used
                # to connect to the LDAP server
                ldap_service_password_file = /etc/krb5kdc/service.keyfile

                # OR, comment out ldap_kdc_dn, ldap_kadmind_dn and
                # ldap_service_password_file above and enable the following
                # two lines, if you skipped the step of creating entries/users
                # for the Kerberos servers

                #ldap_kdc_sasl_mech = EXTERNAL
                #ldap_kadmind_sasl_mech = EXTERNAL
                #ldap_servers = ldapi:///
        }

[logging]
    kdc = STDERR
    admin_server = STDERR
    default = STDERR
EOF

debug_echo "Creating kadm5.acl"
echo "*/admin@${KRB_REALM} *" >  /etc/krb5kdc/kadm5.acl

kdb5_ldap_util -D ${LDAP_ADMIN_DN} -w ${LDAP_ADMIN_PASSWORD} create -subtrees ${LDAP_DN} -r ${KRB_REALM} -s -H ldapi:/// -P ${KRB_MASTER_PASSWORD}

setup_stash "${LDAP_KDC_DN}" "${KDC_PASSWORD}"
setup_stash "${LDAP_KADMIN_DN}" "${KADMIN_PASSWORD}"

debug_echo "Creating Kerberos admin/admin principal"

kadmin.local -q "addprinc -pw ${KRB_ADMIN_PASSWORD} admin/admin@${KRB_REALM}"

debug_echo "Creating ldap keytab"
kadmin.local -q "addprinc -randkey ldap/${DOMAIN_NAME}"
kadmin.local -q "ktadd -k /etc/krb5.keytab ldap/${DOMAIN_NAME}"
kadmin.local -q "addprinc -randkey host/${DOMAIN_NAME}"
kadmin.local -q "ktadd -k /etc/krb5.keytab host/${DOMAIN_NAME}"

chown root:openldap /etc/krb5.keytab
chmod 0640 /etc/krb5.keytab

sed -i "s/#export KRB5_KTNAME=\/etc\/krb5.keytab/export KRB5_KTNAME=\/etc\/krb5.keytab/g" /etc/default/slapd;
