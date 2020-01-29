#!/bin/ash

CreateTunnelAdapter(){
   if [ ! -d "/dev/net" ]; then echo "$(date '+%c') Creating network device classification in /dev"; mkdir /dev/net; fi
   if [ ! -c "/dev/net/tun" ]; then
      echo "$(date '+%c') Creating VPN tunnel adapter"
      mknod -m 0666 /dev/net/tun c 10 200
   fi
}

ConfigureAuthentication(){
   if [ -f "${config_dir}/auth.conf" ]; then
      if [ "${pia_user}" ]; then echo "$(date '+%c') WARNING: ${config_dir}/auth.conf file already exists. User name variable no longer required"; fi
      if [ "${pia_password}" ]; then echo "$(date '+%c') WARNING: ${config_dir}/auth.conf file already exists. Password variable no longer required"; fi
   fi
   if [ ! -f "${config_dir}/auth.conf" ]; then
      echo "$(date '+%c') WARNING: Authentication file, ${config_dir}/auth.conf, does not exist - creating"
      if [ "${pia_user}" ] && [ "${pia_password}" ]; then
         echo "$(date '+%c') Creating authentication file from pia_user and pia_password variables"
         echo "${pia_user}" > "${config_dir}/auth.conf"
         echo "${pia_password}" >> "${config_dir}/auth.conf"
         chmod 600 "${config_dir}/auth.conf"
      else
         if [ -z "${pia_user}" ]; then echo "$(date '+%c') ERROR:   PIA user name not set, connot continue"; exit 1; fi
         if [ -z "${pia_password}" ]; then echo "$(date '+%c') ERROR:   PIA password not set, connot continue"; exit 1; fi
      fi
   fi
}

SetServerLocation(){
   if [ -z "${pia_config_file}" ]; then
      echo "$(date '+%c') WARNING: OpenVPN configuration not set, defaulting to 'Sweden.ovpn'"
      pia_config_file="Sweden.ovpn"
   else
      echo "$(date '+%c') INFO   : OpenVPN configuration set to '${pia_config_file}'"
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
   openvpn --config "${app_base_dir}/${pia_config_file}" --auth-nocache --auth-user-pass "${config_dir}/auth.conf" &
   while [ -z "$(ip ad | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 1; done
   echo "$(date '+%c') OpenVPN Private Internet Access tunnel connected on IP: $(ip ad | grep tun. | grep inet | awk '{print $2}')"
}

LoadPretunnelRules(){
   echo "$(date '+%c') Load pre-tunnel rules"

   echo "$(date '+%c') Allow established and related traffic"
   iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -I OUTPUT -m state --state ESTABLISHED,RELATED  -j ACCEPT

   echo "$(date '+%c') Allow loopback traffic"
   iptables -I INPUT -i lo -j ACCEPT
   iptables -I OUTPUT -o lo -j ACCEPT

   echo "$(date '+%c') Allow LAN ping"
   iptables -I INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p icmp -j ACCEPT

   echo "$(date '+%c') Allow outgoing DNS traffic to OpenVPN PIA servers over LAN adapter"
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.222 -j ACCEPT
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Allow OpenVPN port: ${vpn_port}"
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -p udp --dport "${vpn_port}" -j ACCEPT
   iptables -A INPUT -i "${lan_adapter}" -d "${lan_ip}" -p udp --sport "${vpn_port}" -j ACCEPT

   echo "$(date '+%c') Allow local peer discovery on LAN"
   iptables -A INPUT -i "${lan_adapter}" -s "${lan_ip}" -d "${broadcast_address}" -p udp --dport 6771 -j ACCEPT

   if [ "${sabnzbd_group_id}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for SABnzbd"
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 8080 -j ACCEPT
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 9090 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${sabnzbd_group_id}" -j ACCEPT
   fi
   if [ "${deluge_group_id}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for Deluge"
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 8112 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${deluge_group_id}" -j ACCEPT
   fi
   if [ "${couchpotato_group_id}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for CouchPotato"
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 5050 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${couchpotato_group_id}" -j ACCEPT
   fi
   if [ "${sickgear_group_id}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for SickGear"
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 8081 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${sickgear_group_id}" -j ACCEPT
   fi
   if [ "${headphones_group_id}" ]; then
      echo "$(date '+%c') Adding incoming and outgoing rules for Headphones"
      iptables -A INPUT -i "${lan_adapter}" -s "${nginx_lan_ip_subnet}" -d "${lan_ip}" -p tcp --dport 8181 -j ACCEPT
      iptables -A OUTPUT -m owner --gid-owner "${headphones_group_id}" -j ACCEPT
   fi
}

LoadPosttunnelRules(){
   echo "$(date '+%c') Load post-tunnel rules"

   DeleteLoggingRules

   echo "$(date '+%c') Allow outgoing DNS traffic to OpenVPN PIA servers over the VPN adapter"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 209.222.18.222 -j ACCEPT
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Remove rules allowing outgoing DNS traffic over the LAN adapter"
   iptables -D OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.222 -j ACCEPT
   iptables -D OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Prevent DNS leaks by dropping outgoing DNS traffic to OpenVPN PIA servers over LAN adapter once VPN tunel is up."
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.222 -j DROP
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d 209.222.18.218 -j DROP

   echo "$(date '+%c') Allow non-routable UPnP traffic from VPN adapter"
   iptables -A INPUT -i "${vpn_adapter}" -s "${vpn_ip}" -d 239.255.255.250 -p udp --dport 1900 -j ACCEPT

   echo "$(date '+%c') Allow local peer discovery"
   iptables -A INPUT -i "${vpn_adapter}" -s "${vpn_ip}" -d 239.192.152.143 -p udp --dport 6771 -j ACCEPT

   echo "$(date '+%c') Disable multicast"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 224.0.0.0/24 -p igmp -j DROP

   echo "$(date '+%c') Allow web traffic out"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -p tcp --dport 80 -j ACCEPT
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -p tcp --dport 443 -j ACCEPT

   if [ "${deluge_group_id}" ]; then
      echo "$(date '+%c') Adding outgoing rules for Deluge"
      iptables -A INPUT -i "${vpn_adapter}" -d "${vpn_ip}" -p tcp --dport 58800:59900 -j ACCEPT
      iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -p tcp --sport 58800:59900 -j ACCEPT
      iptables -A INPUT -i "${vpn_adapter}" -d "${vpn_ip}" -p udp --dport 57700 -j ACCEPT
      iptables -A INPUT -i "${vpn_adapter}" -s "${vpn_ip}" -p udp --dport 6771 -j ACCEPT
   fi

   CreateLoggingRules
}

GetLANInfo(){
   lan_ip="$(hostname -i)"
   broadcast_address="$(ip -4 a | grep "${lan_ip}" | awk '{print $4}')"
   nginx_lan_ip_subnet="$(ip -4 r | grep "${lan_ip}" | grep -v via | awk '{print $1}')"
   lan_adapter="$(ip ad | grep eth.$ | awk '{print $7}')"
   vpn_port="$(grep "remote " "${app_base_dir}/${pia_config_file}" | awk '{print $3}')"
   echo "$(date '+%c') LAN Info: ${lan_adapter} ${lan_ip} ${nginx_lan_ip_subnet} ${broadcast_address}"
}

GetVPNInfo(){
   vpn_ip="$(ip ad | grep tun.$ | awk '{print $2}')"
   vpn_adapter="$(ip ad | grep tun.$ | awk '{print $7}')"
   echo "$(date '+%c') VPN Info: ${vpn_adapter} ${vpn_ip} ${vpn_port}"
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

echo -e "\n"
echo "$(date '+%c') ***** Starting OpenVPN Private Internet Access container *****"
CreateTunnelAdapter
ConfigureAuthentication
SetServerLocation
ConfigureLogging
GetLANInfo
ClearAllRules
SetDefaultPolicies
LoadPretunnelRules
CreateLoggingRules
StartOpenVPN
GetVPNInfo
LoadPosttunnelRules
echo "$(date '+%c') ***** Startup of OpenVPN Private Internet Access container complete *****"
while [ "$(ip ad | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 120; done