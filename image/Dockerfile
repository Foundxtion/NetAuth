FROM debian:bookworm-slim

WORKDIR /container
ADD ./docker-entrypoint.sh .
ADD ./config-kerberos.sh .
ADD ./config-openldap.sh .
ADD ./config-slapd.sh .
ADD ./schemas ./schemas

RUN echo "path-include /usr/share/doc/krb5*" >> /etc/dpkg/dpkg.cfg.d/docker && apt-get -y update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install slapd ldap-utils krb5-kdc-ldap krb5-admin-server schema2ldif expect procps libsasl2-modules-gssapi-mit

ENTRYPOINT [ "/container/docker-entrypoint.sh" ]
