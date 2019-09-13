FROM alpine:latest
MAINTAINER boredazfcuk
ENV CONFIGDIR="/config" \
  APPBASE="/OpenVPNPIA" \
  BUILDDEPENDENCIES="curl unzip" \
  APPDEPENDENCIES="openvpn conntrack-tools ulogd"

COPY start-openvpn.sh /usr/local/bin/start-openvpn.sh

RUN echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD STARTED *****" && \
   echo "$(date '+%d/%m/%Y - %H:%M:%S') | Create application directory" && \
   mkdir -p "${APPBASE}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Set permissions on launch file" && \
   chmod +x /usr/local/bin/start-openvpn.sh && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install build dependencies" && \
   apk add --no-cache --no-progress --virtual=build-deps ${BUILDDEPENDENCIES} && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Install dependencies" && \
   apk add --no-cache --no-progress ${APPDEPENDENCIES} && \
   TEMP=$(mktemp -d) && \
   curl -sSL "https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip" -o "${TEMP}/openvpn-strong.zip" && \
   unzip "${TEMP}/openvpn-strong.zip" -d "${APPBASE}" && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Enable iptables logging" && \
   sed -i -e 's/#stack=log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU/stack=log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU/' -e 's/ulogd_syslogemu.log/iptables.log/' /etc/ulogd.conf && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | Clean up" && \
   apk del --no-progress --purge build-deps && \
echo "$(date '+%d/%m/%Y - %H:%M:%S') | ***** BUILD COMPLETE *****"

HEALTHCHECK --start-period=10s --interval=1m --timeout=10s \
  CMD (if [ $(ip -4 a | grep -c tun.) -eq "0" ]; then exit 1; elif [ $(traceroute -m 1 1.1.1.1 | grep -c "$(ip -4 r | grep eth. | grep default | awk '{print $3}')") -ne 0 ]; then exit 1; fi)
  
VOLUME "${CONFIGDIR}"

ENTRYPOINT ["/usr/local/bin/start-openvpn.sh"]
