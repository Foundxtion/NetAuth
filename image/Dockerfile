FROM debian:trixie-slim

WORKDIR /container
ADD ./docker-entrypoint.sh .
ADD ./init-kerberos.sh .
ADD ./init-openldap.sh .
ADD ./init-slapd.sh .
ADD ./schemas ./schemas
ADD ./config-templates ./config-templates

RUN echo "path-include /usr/share/doc/krb5*" >> /etc/dpkg/dpkg.cfg.d/docker && apt-get -y update
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install slapd ldap-utils krb5-kdc-ldap krb5-admin-server schema2ldif expect procps libsasl2-modules-gssapi-mit sasl2-bin

ENTRYPOINT [ "/container/docker-entrypoint.sh" ]
