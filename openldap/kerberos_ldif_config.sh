#!/bin/sh

ldif_folder=/container/service/slapd/assets/config/bootstrap/ldif/custom
kerberos_ldif=$ldif_folder/00-kerberos.ldif

gzip -d /usr/share/doc/krb5-kdc-ldap/kerberos.schema.gz
cp /usr/share/doc/krb5-kdc-ldap/kerberos.schema /etc/ldap/schema/
echo "include /etc/ldap/schema/kerberos.schema" > schema_convert.conf

mkdir /tmp/ldif_output
slaptest -f schema_convert.conf -F /tmp/ldif_output
ldif_file=/tmp/ldif_output/cn\=config/cn\=schema/cn\=\{0\}kerberos.ldif
head -n $(($(cat $ldif_file | wc -l) - 7)) $ldif_file > lol
cat lol  > $ldif_file
rm -f lol

sed -i "3s/.*/dn: cn=kerberos,cn=schema,cn=config/" $ldif_file
sed -i "5s/.*/cn: kerberos/" $ldif_file
cp $ldif_file $kerberos_ldif
