FROM osixia/openldap

EXPOSE 389
EXPOSE 636

COPY ./content.ldif /container/service/slapd/assets/config/bootstrap/ldif/custom/01-content.ldif
COPY ./config.sh /container/config.sh
COPY ./docker-entrypoint.sh /container/docker-entrypoint.sh

ENTRYPOINT [ "/container/docker-entrypoint.sh" ]
