FROM alpine:3.23

ARG PG_MAJOR=18
RUN apk add --no-cache postgresql${PG_MAJOR}-client ca-certificates \
    && mkdir /backups

COPY --chmod=755 entrypoint.sh /usr/local/bin/pg-backup-manager
WORKDIR /backups
ENTRYPOINT ["/usr/local/bin/pg-backup-manager"]
CMD ["help"]
