#!/bin/ash

CreateTunnelAdapter(){
   if [ ! -d "/dev/net" ]; then echo "$(date '+%c') Creating network device classification in /dev"; mkdir /dev/net; fi
   if [ ! -c "/dev/net/tun" ]; then
      echo "$(date '+%c') Creating VPN tunnel adapter"
      mknod -m 0666 /dev/net/tun c 10 200
   fi
}

ConfigureAuthentication(){
   if [ -f "${CONFIGDIR}/auth.conf" ]; then
      if [ ! -z "${PIAUSER}" ]; then echo "$(date '+%c') WARNING: ${CONFIGDIR}/auth.conf file already exists. User name variable no longer required"; fi
      if [ ! -z "${PIAPASSWORD}" ]; then echo "$(date '+%c') WARNING: ${CONFIGDIR}/auth.conf file already exists. Password variable no longer required"; fi
   fi
   if [ ! -f "${CONFIGDIR}/auth.conf" ]; then
      echo "$(date '+%c') WARNING: Authentication file, ${CONFIGDIR}/auth.conf, does not exist - creating"
      if [ ! -z "${PIAUSER}" ] && [ ! -z "${PIAPASSWORD}" ]; then
         echo "$(date '+%c') Creating authentication file from PIAUSER and PIAPASSWORD variables"
         echo "${PIAUSER}" > "${CONFIGDIR}/auth.conf"
         echo "${PIAPASSWORD}" >> "${CONFIGDIR}/auth.conf"
         chmod 600 "${CONFIGDIR}/auth.conf"
      else
         if [ -z "${PIAUSER}" ]; then echo "$(date '+%c') ERROR:   PIA user name not set, connot continue"; exit 1; fi
         if [ -z "${PIAPASSWORD}" ]; then echo "$(date '+%c') ERROR:   PIA password not set, connot continue"; exit 1; fi
      fi
   fi
}

SetServerLocation(){
   if [ -z "${CONFIGFILE}" ]; then
      echo "$(date '+%c') WARNING: OpenVPN configuration not set, defaulting to 'Sweden.ovpn'"
      CONFIGFILE="Sweden.ovpn"
   else
      echo "$(date '+%c') INFO   : OpenVPN configuration set to '${CONFIGFILE}'"
   fi
}

ConfigureLogging(){
   echo "$(date '+%c') Logging to /var/log/iptables.log"
   sed -i -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_inppkt_NFLOG.so\"%plugin=\"/usr/lib/ulogd/ulogd_inppkt_NFLOG.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_raw2packet_BASE.so\"%plugin=\"/usr/lib/ulogd/ulogd_raw2packet_BASE.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_IFINDEX.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_IFINDEX.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_IP2STR.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_IP2STR.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_PRINTPKT.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_PRINTPKT.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_output_LOGEMU.so\"%plugin=\"/usr/lib/ulogd/ulogd_output_LOGEMU.so\"%" \
      -e 's/^#stack=log1:NFLOG,base1/stack=log1:NFLOG,base1/' \
      -e 's/ulogd_syslogemu.log/iptables.log/' /etc/ulogd.conf
   if [ ! -f /var/log/iptables.log ]; then touch /var/log/iptables.log; fi
   /usr/sbin/ulogd &
   tail -Fn0 /var/log/iptables.log &
}

CreateLoggingRules(){

   echo "$(date '+%c') Create logging chains"
   iptables -N LOG_IN
   iptables -N LOG_FW
   iptables -N LOG_OUT

   echo "$(date '+%c') Create chain rules"
   iptables -A LOG_IN -j NFLOG --nflog-group 0 --nflog-prefix "IN DENY  : "
   iptables -A LOG_IN -j DROP
   iptables -A LOG_FW -j NFLOG --nflog-group 0 --nflog-prefix "FW DENY  : "
   iptables -A LOG_FW -j DROP
   iptables -A LOG_OUT -j NFLOG --nflog-group 0 --nflog-prefix "OUT ALLOW: "
   iptables -A LOG_OUT -j ACCEPT

   echo "$(date '+%c') Enable chains"
   iptables -A INPUT -j LOG_IN
   iptables -A FORWARD -j LOG_FW
   iptables -A OUTPUT -j LOG_OUT

}

DeleteLoggingRules(){

   echo "$(date '+%c') Delete chain rules"
   iptables -D LOG_IN -j NFLOG --nflog-group 0 --nflog-prefix "IN DENY  : "
   iptables -D LOG_IN -j DROP
   iptables -D LOG_FW -j NFLOG --nflog-group 0 --nflog-prefix "FW DENY  : "
   iptables -D LOG_FW -j DROP
   iptables -D LOG_OUT -j NFLOG --nflog-group 0 --nflog-prefix "OUT ALLOW: "
   iptables -D LOG_OUT -j ACCEPT

   echo "$(date '+%c') Delete chain references"
   iptables -D INPUT -j LOG_IN
   iptables -D FORWARD -j LOG_FW
   iptables -D OUTPUT -j LOG_OUT

   echo "$(date '+%c') Delete logging chains"
   iptables -X LOG_IN
   iptables -X LOG_FW
   iptables -X LOG_OUT

}

StartOpenVPN(){

   echo "$(date '+%c') Starting OpenVPN client"
   openvpn --config "${APPBASE}/${CONFIGFILE}" --auth-nocache --auth-user-pass "${CONFIGDIR}/auth.conf" &
   while [ -z "$(ip ad | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 1; done
   echo "$(date '+%c') OpenVPN Private Internet Access tunnel connected on IP: $(ip ad | grep tun. | grep inet | awk '{print $2}')"

}

InitialisePretunnelRules(){

   echo "$(date '+%c') Initialise pre-tunnel rules"

   echo "$(date '+%c') Allow established and related traffic"
   iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -I OUTPUT -m state --state ESTABLISHED,RELATED  -j ACCEPT

   echo "$(date '+%c') Allow loopback traffic"
   iptables -I INPUT -i lo -j ACCEPT
   iptables -I OUTPUT -o lo -j ACCEPT

   echo "$(date '+%c') Allow LAN ping"
   iptables -I INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p icmp -j ACCEPT

   echo "$(date '+%c') Allow outgoing DNS traffic to OpenVPN PIA servers over LAN adapter"
   iptables -A OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.222 -j ACCEPT
   iptables -A OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Allow OpenVPN port: ${VPNPORT}"
   iptables -A OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -p udp --dport "${VPNPORT}" -j ACCEPT
   iptables -A INPUT -i "${LANADAPTER}" -d "${LANIP}" -p udp --sport "${VPNPORT}" -j ACCEPT

   echo "$(date '+%c') Allow local peer discovery on LAN"
   iptables -A INPUT -i "${LANADAPTER}" -s "${LANIP}" -d "${BCASTADDR}" -p udp --dport 6771 -j ACCEPT

   if [ ! -z "${SABNZBDGID}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for SABnzbd"
      iptables -A INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p tcp --dport 8080 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${SABNZBDGID}" -j ACCEPT
   fi
   if [ ! -z "${DELUGEGID}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for Deluge"
      iptables -A INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p tcp --dport 8112 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${DELUGEGID}" -j ACCEPT
   fi
   if [ ! -z "${COUCHPOTATOGID}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for CouchPotato"
      iptables -A INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p tcp --dport 5050 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${COUCHPOTATOGID}" -j ACCEPT
   fi
   if [ ! -z "${SICKGEARGID}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for SickGear"
      iptables -A INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p tcp --dport 8081 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${SICKGEARGID}" -j ACCEPT
   fi
   if [ ! -z "${HEADPHONESGID}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for Headphones"
      iptables -A INPUT -i "${LANADAPTER}" -s "${LANIPSUBNET}" -d "${LANIP}" -p tcp --dport 8181 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${HEADPHONESGID}" -j ACCEPT
   fi

   echo "$(date '+%c') Save iptables pre-tunnel default configuration"
   iptables-save > "${CONFIGDIR}/rules.v4.pretunnel.default"
   echo "$(date '+%c') Create custom pre-tunnel rules file from default configuration"
   cp "${CONFIGDIR}/rules.v4.pretunnel.default" "${CONFIGDIR}/rules.v4.pretunnel.custom"

}

InitialisePosttunnelRules(){

   echo "$(date '+%c') Initialise post-tunnel rules"

   echo "$(date '+%c') Allow outgoing DNS traffic to OpenVPN PIA servers over VPN adapter"
   iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -d 209.222.18.222 -j ACCEPT
   iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Prevent DNS leaks by dropping outgoing DNS traffic to OpenVPN PIA servers over LAN adapter once VPN tunel is up."
   iptables -A OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.222 -j DROP
   iptables -A OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.218 -j DROP

   echo "$(date '+%c') Allow non-routable UPnP traffic from VPN adapter"
   iptables -A INPUT -i "${VPNADAPTER}" -s "${VPNIP}" -d 239.255.255.250 -p udp --dport 1900 -j ACCEPT

   echo "$(date '+%c') Allow local peer discovery"
   iptables -A INPUT -i "${VPNADAPTER}" -s "${VPNIP}" -d 239.192.152.143 -p udp --dport 6771 -j ACCEPT

   echo "$(date '+%c') Disable multicast"
   iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -d 224.0.0.0/24 -p igmp -j DROP

   echo "$(date '+%c') Allow web traffic out"
   iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -p tcp --dport 80 -j ACCEPT
   iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -p tcp --dport 443 -j ACCEPT

   if [ ! -z "${DELUGEGID}" ]; then
      echo "$(date '+%c') Adding outgoing rules for Deluge"
      iptables -A INPUT -i "${VPNADAPTER}" -d "${VPNIP}" -p tcp --dport 58800:59900 -j ACCEPT
      iptables -A OUTPUT -o "${VPNADAPTER}" -s "${VPNIP}" -p tcp --sport 58800:59900 -j ACCEPT
      iptables -A INPUT -i "${VPNADAPTER}" -d "${VPNIP}" -p udp --dport 53160 -j ACCEPT
      iptables -A INPUT -i "${VPNADAPTER}" -s "${VPNIP}" -p udp --dport 6771 -j ACCEPT
   fi

   iptables-save > "${CONFIGDIR}/rules.v4.posttunnel.default"
   echo "$(date '+%c') Create custom post-tunnel rules file from default configuration"
   cp "${CONFIGDIR}/rules.v4.posttunnel.default" "${CONFIGDIR}/rules.v4.posttunnel.custom"

}

GetLANInfo(){

   LANIP="$(hostname -i)"
   BCASTADDR="$(ip -4 a | grep "${LANIP}" | awk '{print $4}')"
   LANIPSUBNET="$(ip -4 r | grep "${LANIP}" | awk '{print $1}')"
   LANADAPTER="$(ip ad | grep eth.$ | awk '{print $7}')"
   VPNPORT="$(grep "remote " "${APPBASE}/${CONFIGFILE}" | awk '{print $3}')"
   echo "$(date '+%c') LAN Info: ${LANADAPTER} ${LANIP} ${LANIPSUBNET} ${BCASTADDR}"

}

GetVPNInfo(){

   VPNIP="$(ip ad | grep tun.$ | awk '{print $2}')"
   VPNADAPTER="$(ip ad | grep tun.$ | awk '{print $7}')"
   echo "$(date '+%c') VPN Info: ${VPNADAPTER} ${VPNIP} ${VPNPORT}"

}

ClearAllRules(){

   echo "$(date '+%c') Clear iptables configuration"
   conntrack -F >/dev/null 2>&1
   iptables -F
   iptables -X

}

SetDefaultPolicies(){

   echo "$(date '+%c') Set default policies"
   iptables -P INPUT ACCEPT
   iptables -P FORWARD ACCEPT
   iptables -P OUTPUT ACCEPT

}

CreatePretunnelRules(){

   if [ ! -f "${CONFIGDIR}/rules.v4.pretunnel.default" ]; then
      ClearAllRules
      SetDefaultPolicies
      InitialisePretunnelRules
   fi

   echo "$(date '+%c') Load custom pre-tunnel rules"
   iptables-restore < "${CONFIGDIR}/rules.v4.pretunnel.custom"
   CreateLoggingRules

}

CreatePosttunnelRules(){

   if [ ! -f "${CONFIGDIR}/rules.v4.posttunnel.default" ]; then
      ClearAllRules
      SetDefaultPolicies
      InitialisePosttunnelRules
      ClearAllRules
      CreatePretunnelRules
   fi

   iptables -D OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.222 -j ACCEPT
   iptables -D OUTPUT -o "${LANADAPTER}" -s "${LANIP}" -d 209.222.18.218 -j ACCEPT
   DeleteLoggingRules

   echo "$(date '+%c') Load custom post-tunnel rules"
   iptables-restore --noflush < "${CONFIGDIR}/rules.v4.posttunnel.custom"

   CreateLoggingRules

}

echo "$(date '+%c') ***** Starting OpenVPN Private Internet Access container *****"
CreateTunnelAdapter
ConfigureAuthentication
SetServerLocation
ConfigureLogging
GetLANInfo
CreatePretunnelRules
StartOpenVPN
GetVPNInfo
CreatePosttunnelRules
while [ ! -z "$(ip ad | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 120; done