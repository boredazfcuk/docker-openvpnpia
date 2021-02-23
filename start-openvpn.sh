#!/bin/ash

Initialise(){
   echo
   echo "$(date '+%c') ***** Starting OpenVPN Private Internet Access container *****"
   echo "$(date '+%c') $(cat /etc/*-release | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | sed 's/"//g')"
}

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
         echo "${pia_user}" > "/auth.conf"
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
   echo "$(date '+%c') Logging to ${config_dir}/log/iptables.log"
   sed -i -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_inppkt_NFLOG.so\"%plugin=\"/usr/lib/ulogd/ulogd_inppkt_NFLOG.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_raw2packet_BASE.so\"%plugin=\"/usr/lib/ulogd/ulogd_raw2packet_BASE.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_IFINDEX.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_IFINDEX.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_IP2STR.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_IP2STR.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_filter_PRINTPKT.so\"%plugin=\"/usr/lib/ulogd/ulogd_filter_PRINTPKT.so\"%" \
      -e "s%^#plugin=\"/usr/lib/ulogd/ulogd_output_LOGEMU.so\"%plugin=\"/usr/lib/ulogd/ulogd_output_LOGEMU.so\"%" \
      -e 's/^#stack=log1:NFLOG,base1/stack=log1:NFLOG,base1/' \
      -e 's/ulogd_syslogemu.log/iptables.log/' /etc/ulogd.conf
   if [ ! -d "${config_dir}/log" ]; then mkdir -p "${config_dir}/log"; fi
   if [ ! -f "${config_dir}/log/iptables.log" ]; then touch "${config_dir}/log/iptables.log"; fi
   if [ -f "/var/log/iptables.log" ]; then rm "/var/log/iptables.log"; fi
   if [ ! -L "/var/log/iptables.log" ]; then ln -s "${config_dir}/log/iptables.log" "/var/log/iptables.log"; fi
   /usr/sbin/ulogd &
   if [ "${follow_iptables_log}" ]; then
      tail -Fn0 "${config_dir}/log/iptables.log" &
   fi
}

CreateLoggingRules(){
   echo "$(date '+%c') Create logging chains"
   iptables -N LOG_IN
   iptables -N LOG_FW
   iptables -N LOG_OUT

   echo "$(date '+%c') Create chain rules"
   iptables -A LOG_IN -j NFLOG --nflog-group 0 --nflog-prefix "IN DENY   : "
   iptables -A LOG_IN -j ACCEPT
   # iptables -A LOG_IN -j DROP
   iptables -A LOG_FW -j NFLOG --nflog-group 0 --nflog-prefix "FW DENY   : "
   iptables -A LOG_FW -j ACCEPT
   # iptables -A LOG_FW -j DROP
   iptables -A LOG_OUT -j NFLOG --nflog-group 0 --nflog-prefix "OUT ALLOW : "
   iptables -A LOG_OUT -j ACCEPT

   echo "$(date '+%c') Enable chains"
   iptables -A INPUT -j LOG_IN
   iptables -A FORWARD -j LOG_FW
   iptables -A OUTPUT -j LOG_OUT
}

DeleteLoggingRules(){
   echo "$(date '+%c') Delete chain rules"
   iptables -D LOG_IN -j NFLOG --nflog-group 0 --nflog-prefix "IN DENY   : "
   iptables -D LOG_IN -j ACCEPT
   # iptables -D LOG_IN -j DROP
   iptables -D LOG_FW -j NFLOG --nflog-group 0 --nflog-prefix "FW DENY   : "
   iptables -D LOG_FW -j ACCEPT
   # iptables -D LOG_FW -j DROP
   iptables -D LOG_OUT -j NFLOG --nflog-group 0 --nflog-prefix "OUT ALLOW : "
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
   default_gateway="$(ip route | grep "^default" | awk '{print $3}')"
   echo "$(date '+%c') Default gateway: ${default_gateway}"
   echo "$(date '+%c') Create additional route to Docker host network ${host_lan_ip_subnet} via ${default_gateway}"
   ip route add "${host_lan_ip_subnet}" via "${default_gateway}"
   echo "$(date '+%c') Starting OpenVPN client"
   openvpn --config "${app_base_dir}/${pia_config_file}" --auth-nocache --auth-user-pass "${config_dir}/auth.conf" --mute-replay-warnings &
   while [ -z "$(ip addr | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 1; done
   echo "$(date '+%c') OpenVPN Private Internet Access tunnel connected on IP: $(ip ad | grep tun. | grep inet | awk '{print $2}')"
}

LoadPretunnelRules(){
   echo "$(date '+%c') Load pre-tunnel rules"

   echo "$(date '+%c') Allow established and related traffic"
   iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -I OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

   echo "$(date '+%c') Allow loopback traffic"
   iptables -I INPUT -i lo -j ACCEPT
   iptables -I OUTPUT -o lo -j ACCEPT

   echo "$(date '+%c') Allow LAN ping"
   iptables -I INPUT -i "${lan_adapter}" -s "${docker_lan_ip_subnet}" -d "${lan_ip}" -p icmp -j ACCEPT
   iptables -I INPUT -i "${lan_adapter}" -s "${host_lan_ip_subnet}" -d "${lan_ip}" -p icmp -j ACCEPT

   echo "$(date '+%c') Allow outgoing DNS traffic to host network over LAN adapter"
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d "${host_lan_ip_subnet}" -p udp --dport 53 -j ACCEPT
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -d "${host_lan_ip_subnet}" -p tcp --dport 53 -j ACCEPT

   echo "$(date '+%c') Allow OpenVPN port: ${vpn_port}"
   iptables -A OUTPUT -o "${lan_adapter}" -s "${lan_ip}" -p udp --dport "${vpn_port}" -j ACCEPT
   iptables -A INPUT -i "${lan_adapter}" -d "${lan_ip}" -p udp --sport "${vpn_port}" -j ACCEPT
}

LoadPosttunnelRules(){
   echo "$(date '+%c') Load post-tunnel rules"

   DeleteLoggingRules

   echo "$(date '+%c') Allow ping from Docker LAN subnet to be forwarded from LAN to VPN"
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p icmp -j ACCEPT

   echo "$(date '+%c') Allow pong to Docker LAN subnet to be forwarded from VPN to LAN"
   iptables -I FORWARD -i "${vpn_adapter}" -o "${lan_adapter}" -d "${docker_lan_ip_subnet}" -p icmp -j ACCEPT

   echo "$(date '+%c') Allow DNS requests from Docker LAN subnet to be forwarded from LAN to VPN"
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p udp --dport 53 -j ACCEPT

   echo "$(date '+%c') Allow DNS replies to Docker LAN subnet to be forwarded from VPN to LAN"
   iptables -I FORWARD -i "${vpn_adapter}" -o "${lan_adapter}" -d "${docker_lan_ip_subnet}" -p udp --sport 53 -j ACCEPT

   echo "$(date '+%c') Allow HTTP requests from Docker LAN subnet to be forwarded from LAN to VPN"
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p tcp --dport 80 -j ACCEPT

   echo "$(date '+%c') Allow HTTP replies to Docker LAN subnet to be forwarded from VPN to LAN"
   iptables -I FORWARD -i "${vpn_adapter}" -o "${lan_adapter}" -d "${docker_lan_ip_subnet}" -p tcp --sport 80 -j ACCEPT

   echo "$(date '+%c') Allow HTTPS requests from Docker LAN subnet to be forwarded from LAN to VPN"
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p tcp --dport 443 -j ACCEPT

   echo "$(date '+%c') Allow HTTPS replies to Docker LAN subnet to be forwarded from VPN to LAN"
   iptables -I FORWARD -i "${vpn_adapter}" -o "${lan_adapter}" -d "${docker_lan_ip_subnet}" -p tcp --sport 443 -j ACCEPT

   echo "$(date '+%c') Allow outgoing DNS traffic to OpenVPN PIA servers over the VPN adapter"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 209.222.18.222 -j ACCEPT
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 209.222.18.218 -j ACCEPT

   echo "$(date '+%c') Allow non-routable UPnP traffic from VPN adapter"
   iptables -A INPUT -i "${vpn_adapter}" -s "${vpn_ip}" -d 239.255.255.250 -p udp --dport 1900 -j ACCEPT

   echo "$(date '+%c') Allow local peer discovery"
   iptables -A INPUT -i "${vpn_adapter}" -s "${vpn_ip}" -d 239.192.152.143 -p udp --dport 6771 -j ACCEPT

   echo "$(date '+%c') Disable multicast"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d 224.0.0.0/24 -p igmp -j DROP

   echo "$(date '+%c') Allow web traffic out"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -p tcp --dport 80 -j ACCEPT
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -p tcp --dport 443 -j ACCEPT

   echo "$(date '+%c') Allow traceroute traffic from VPN IP to VPN default gateway out via VPN adapter"
   iptables -A OUTPUT -o "${vpn_adapter}" -s "${vpn_ip}" -d "${vpn_default_gateway}" -p udp --dport 33434:33534 -j ACCEPT

   echo "$(date '+%c') Allow outgoing requests from Docker LAN subnet to be forwarded from LAN to VPN"
   iptables -I INPUT -i "${lan_adapter}" -d "${lan_ip}" -p udp -j ACCEPT
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p udp --sport 57700 -j ACCEPT
   iptables -I FORWARD -i "${vpn_adapter}" -o "${lan_adapter}" -d "${docker_lan_ip_subnet}" -p udp --sport 6881 --dport 57700 -j ACCEPT
   iptables -I FORWARD -i "${lan_adapter}" -o "${lan_adapter}" -s "${docker_lan_ip_subnet}" -p udp --sport 57700 --dport 57700 -j ACCEPT
   iptables -I FORWARD -i "${lan_adapter}" -o "${lan_adapter}" -s "${docker_lan_ip_subnet}" -p tcp --dport 57700 -j ACCEPT
   iptables -I FORWARD -i "${lan_adapter}" -o "${vpn_adapter}" -s "${docker_lan_ip_subnet}" -p tcp --sport 58800:59900 -j ACCEPT
   iptables -I FORWARD -i "${lan_adapter}" -o "${lan_adapter}" -s "${docker_lan_ip_subnet}" -p udp --sport 57700 -j ACCEPT

   CreateLoggingRules
}

GetLANInfo(){
   lan_ip="$(hostname -i)"
   host_network_route="${lan_ip%.*}.1"
   broadcast_address="$(ip -4 addr | grep "${lan_ip}" | awk '{print $4}')"
   docker_lan_ip_subnet="$(ip -4 route | grep "${lan_ip}" | grep -v via | awk '{print $1}')"
   lan_adapter="$(ip -o addr | grep eth. | awk '{print $2}')"
   vpn_port="$(grep "remote " "${app_base_dir}/${pia_config_file}" | awk '{print $3}')"
   echo "$(date '+%c') LAN Adapter: ${lan_adapter}"
   echo "$(date '+%c') LAN IP Address: ${lan_ip}"
   echo "$(date '+%c') Host network: ${host_lan_ip_subnet}"
   echo "$(date '+%c') Route to host network: ${host_network_route}"
   echo "$(date '+%c') Docker network: ${docker_lan_ip_subnet}"
   echo "$(date '+%c') Docker network broadcast address: ${broadcast_address}"
}

GetVPNInfo(){
   vpn_cidr_ip="$(ip -o addr | grep tun. | awk '{print $4}')"
   vpn_ip="${vpn_cidr_ip%/*}"
   vpn_adapter="$(ip -o addr | grep tun. | awk '{print $2}')"
   vpn_default_gateway="$(route | grep tun.$ | grep default | awk '{print $2}')"
   echo "$(date '+%c') VPN Info: ${vpn_adapter} ${vpn_cidr_ip} ${vpn_ip} ${vpn_port}"
   echo "$(date '+%c') Enable NAT on VPN adapter"
   iptables -t nat -A POSTROUTING -o "${vpn_adapter}" -j MASQUERADE
}

CheckPortForwardingServer(){
   case "${pia_config_file/.ovpn/}" in
      "CA Toronto"|"CA Montreal"|"CA Vancouver"|"Czech Republic"|"DE Berlin"|"DE Frankfurt"|France|Israel|Romania|Spain|Switzerland|Sweden)
         port_forward_capable="True"
         echo "$(date '+%c') ${pia_config_file/.ovpn/} server is capable of port forwarding."
         ;;
      *)
         echo "$(date '+%c') ${pia_config_file/.ovpn/} server is not capable of port forwarding. To enable port forwarding, please select on of the following VPN server profiles: CA Toronto, CA Montreal, CA Vancouver, Czech Republic, DE Berlin, DE Frankfurt, France, Israel, Romania, Spain, Switzerland or Sweden"
   esac
}   

GetPortForwardingPort(){
   if [ "${port_forward_capable}" = "True" ]; then
      echo "$(date '+%c') Loading port forward assignment information..."
      client_id="$(head -n 100 /dev/urandom | sha256sum | tr -d " -")"
      echo "$(date '+%c') Client ID: ${client_id}"
      forwarded_port="$(wget -O- --tries=3 "http://209.222.18.222:2000/?client_id=$client_id" 2>/dev/null)"
      if [ -z "${forwarded_port}" ]; then
         echo "$(date '+%c') ERROR: Port forwarding is already activated on this connection, has expired, you are not connected to a PIA region that supports port forwarding, or the remote server is down"
      else
         forwarded_port="${forwarded_port//[^0-9]/}"
         echo "$(date '+%c') Port to use for port forwarding: ${forwarded_port}"
      fi
   fi
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

Initialise
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
CheckPortForwardingServer
GetPortForwardingPort
LoadPosttunnelRules
echo "$(date '+%c') ***** Startup of OpenVPN Private Internet Access container complete *****"
while [ "$(ip addr | grep tun. | grep inet | awk '{print $2}')" ]; do sleep 120; done
echo "$(date '+%c') ***** Connection dropped. Restarting container *****"