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
    
    kdb5_ldap_util -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" stashsrvpw -f /netauth/service.keyfile "$dn" < input_file
    rm -f input_file
}

unique()
{
	echo "$@" | tr ' ' '\n' | sort -u
}

kdb5_ldap_util -D ${LDAP_ADMIN_DN} -w ${LDAP_ADMIN_PASSWORD} create -subtrees ${LDAP_DN} -r ${KRB_REALM} -s -H ldapi:/// -P ${KRB_MASTER_PASSWORD}

debug_echo "Creating stash for KDC and KADMIN principals"
setup_stash "${LDAP_KDC_DN}" "${KDC_PASSWORD}"
setup_stash "${LDAP_KADMIN_DN}" "${KADMIN_PASSWORD}"

debug_echo "Creating Kerberos admin/admin principal"

kadmin.local -q "addprinc -pw ${KRB_ADMIN_PASSWORD} admin/admin@${KRB_REALM}"

debug_echo "Creating LDAP keytab"
principals=$(unique "${DOMAIN_NAME}" "$(hostname -f)")
for princ in principals; do
	kadmin.local -q "addprinc -randkey ldap/${princ}"
	kadmin.local -q "ktadd -k /netauth/krb5.keytab ldap/${princ}"
	kadmin.local -q "addprinc -randkey host/${princ}"
	kadmin.local -q "ktadd -k /netauth/krb5.keytab host/${princ}"
done

chown root:openldap /netauth/krb5.keytab
chmod 0640 /netauth/krb5.keytab

sed -i "s/#export KRB5_KTNAME=\/etc\/krb5.keytab/export KRB5_KTNAME=\/netauth\/krb5.keytab/g" /netauth/slapd;
