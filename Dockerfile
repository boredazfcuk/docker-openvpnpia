FROM alpine:latest
MAINTAINER boredazfcuk
ARG BUILDDEPENDENCIES="curl unzip"
ARG APPDEPENDENCIES="openvpn conntrack-tools ulogd"
ENV CONFIGDIR="/config" \
  APPBASE="/OpenVPNPIA"


RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
   echo "$(date '+%d/%m/%Y - %H:%M:%S') | Create application directory" && \
   mkdir -p "${APPBASE}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install build dependencies" && \
   apk add --no-cache --no-progress --virtual=build-deps ${BUILDDEPENDENCIES} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install dependencies" && \
   apk add --no-cache --no-progress ${APPDEPENDENCIES} && \
   TEMP="$(mktemp -d)" && \
   curl -sSL "https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip" -o "${TEMP}/openvpn-strong.zip" && \
   unzip "${TEMP}/openvpn-strong.zip" -d "${APPBASE}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Clean up" && \
   rm -r "${TEMP}" && \
   apk del --no-progress --purge build-deps

COPY start-openvpn.sh /usr/local/bin/start-openvpn.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set permissions on scripts" && \
   chmod +x /usr/local/bin/start-openvpn.sh /usr/local/bin/healthcheck.sh && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
  CMD /usr/local/bin/healthcheck.sh
  
VOLUME "${CONFIGDIR}"
WORKDIR "${APPBASE}"

ENTRYPOINT ["/usr/local/bin/start-openvpn.sh"]
