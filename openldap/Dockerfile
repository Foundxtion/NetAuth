FROM osixia/openldap

EXPOSE 389
EXPOSE 636

COPY ./content.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/01-content.ldif
COPY ./database.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/02-database.ldif

COPY ./config.sh /container/config.sh
COPY ./docker-entrypoint.sh /container/docker-entrypoint.sh
COPY ./kerberos_ldif_config.sh /container/kerberos_ldif_config.sh

RUN /container/kerberos_ldif_config.sh

ENTRYPOINT [ "/container/docker-entrypoint.sh" ]
