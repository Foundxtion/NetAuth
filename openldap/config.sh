#!/bin/sh

cat > /etc/krb5.conf << EOF
[libdefaults]
	default_realm = $KRB5_REALM
	ignore_acceptor_hostname = true
	rdns = false
EOF

if [ -n "$KRB5_KDC" ]; then
	cat >> /etc/krb5.conf << EOF
[realms]
	$KRB5_REALM = {
		kdc = $KRB5_KDC
	}
EOF

fi

cat >> /etc/krb5.conf << EOF
[domain_realm]
	$LDAP_DOMAIN = $KRB5_REALM
	.$LDAP_DOMAIN = $KRB5_REALM
EOF
