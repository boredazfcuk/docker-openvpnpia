FROM alpine:latest
MAINTAINER boredazfcuk
ARG build_dependencies="curl unzip"
ARG app_dependencies="openvpn conntrack-tools ulogd"
ENV config_dir="/config" \
  app_base_dir="/OpenVPNPIA"


RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
   echo "$(date '+%d/%m/%Y - %H:%M:%S') | Create application directory" && \
   mkdir -p "${app_base_dir}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install build dependencies" && \
   apk add --no-cache --no-progress --virtual=build-deps ${build_dependencies} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install dependencies" && \
   apk add --no-cache --no-progress ${app_dependencies} && \
   temp_dir="$(mktemp -d)" && \
   curl -sSL "https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip" -o "${temp_dir}/openvpn-strong.zip" && \
   unzip "${temp_dir}/openvpn-strong.zip" -d "${app_base_dir}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Clean up" && \
   rm -r "${temp_dir}" && \
   apk del --no-progress --purge build-deps

COPY start-openvpn.sh /usr/local/bin/start-openvpn.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set permissions on scripts" && \
   chmod +x /usr/local/bin/start-openvpn.sh /usr/local/bin/healthcheck.sh && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
  CMD /usr/local/bin/healthcheck.sh
  
VOLUME "${config_dir}"
WORKDIR "${app_base_dir}"

ENTRYPOINT ["/usr/local/bin/start-openvpn.sh"]
