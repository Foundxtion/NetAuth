FROM alpine:3.15

RUN apk add --no-cache krb5-server krb5 openldap-clients

WORKDIR /container

ADD docker-entrypoint.sh .

EXPOSE 749 464 88

ENTRYPOINT ["./docker-entrypoint.sh"]
