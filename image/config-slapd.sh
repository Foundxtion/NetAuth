#!/usr/bin/expect

spawn dpkg-reconfigure slapd
expect "Omit OpenLDAP server configuration?"
send "no\r"
expect "DNS domain name:"
send "{{ DOMAIN_NAME }}\r"
expect "Organization name:"
send "{{ LDAP_ORGANISATION }}\r"
expect "Administrator password:"
send "admin\r"
expect "Confirm password:"
send "admin\r"
expect "Do you want the database to be removed when slapd is purged?"
send "yes\r"
expect "Move old database?"
send "no\r"
expect eof

