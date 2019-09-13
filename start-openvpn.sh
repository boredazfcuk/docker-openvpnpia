#!/bin/sh

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
         chmod 700 "${CONFIGDIR}/auth.conf"
      else
         if [ -z "${PIAUSER}" ]; then echo "$(date '+%c') ERROR:   PIA user name not set, connot continue"; exit 1; fi
         if [ -z "${PIAPASSWORD}" ]; then echo "$(date '+%c') ERROR:   PIA password not set, connot continue"; exit 1; fi
      fi
   fi
}

SetConfigFile(){
   if [ -z "${CONFIGFILE}" ]; then
      echo "$(date '+%c') WARNING: OpenVPN config file not set, defaulting to 'Sweden.ovpn'"
      CONFIGFILE="Sweden.ovpn"
   fi
}

EnableLogging(){
   if [ "${LOGGING}" = "True" ]; then
      echo "$(date '+%c') Debug logging enabled, logging to /var/log/iptables.log"
      /usr/sbin/ulogd &
      if [ ! -f /var/log/iptables.log ]; then touch /var/log/iptables.log; fi
      tail -Fn0 /var/log/iptables.log &
   fi
}

PreTunnelFirewallRules(){
   LANIPADDR="$(hostname -i)"
   BCASTADDR="$(ip -4 a | grep "${LANIPADDR}" | awk '{print $4}')"
   LANIPSUBNET="$(ip -4 r | grep "${LANIPADDR}" | awk '{print $1}')"
   echo "$(date '+%c') Clear iptables configuration"
   iptables -F
   iptables -X
   echo "$(date '+%c') Set default policies"
   iptables -P INPUT ACCEPT
   iptables -P FORWARD ACCEPT
   iptables -P OUTPUT ACCEPT
   echo "$(date '+%c') Create logging chains"
   iptables -N LOG_IN
   iptables -N LOG_FW
   iptables -N LOG_OUT
   echo "$(date '+%c') Configure logging chains"
   iptables -A LOG_IN -j NFLOG --nflog-prefix "IN: "
   iptables -A LOG_IN -j DROP
   iptables -A LOG_FW -j NFLOG --nflog-prefix "FW :"
   iptables -A LOG_FW -j DROP
   iptables -A LOG_OUT -j NFLOG --nflog-prefix "OUT:"
   iptables -A LOG_OUT -j ACCEPT
   echo "$(date '+%c') Allow loopback traffic"
   iptables -I INPUT -i lo -j ACCEPT
   iptables -I OUTPUT -o lo -j ACCEPT
   echo "$(date '+%c') Allow established and related traffic"
   iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
   iptables -A OUTPUT -m state --state ESTABLISHED,RELATED  -j ACCEPT
   echo "$(date '+%c') Configure OpenVPN rules"
   iptables -A INPUT -i eth+ -d "${LANIPADDR}" -p udp --sport 1197 -j ACCEPT
   iptables -A OUTPUT -o eth+ -d "${LANIPADDR}" -p udp --sport 1197 -j ACCEPT
}

StartOpenVPN(){
   echo "$(date '+%c') Starting OpenVPN client"
   set -- "$@" '--config' "${APPBASE}/${CONFIGFILE}"
   openvpn "$@" "--auth-nocache" "--auth-user-pass" "${CONFIGDIR}/auth.conf"
}

PostTunnelFirewallRules(){
   echo "$(date '+%c') Send unmatched traffic to log file"
   iptables -A INPUT -j LOG_IN
   iptables -A FORWARD -j LOG_FW
   iptables -A OUTPUT -j LOG_OUT
   echo "$(date '+%c') Save iptables configuration"
   iptables-save >"${CONFIGDIR}/rules.v4.default"
}

echo "$(date '+%c') ***** Starting OpenVPN Private Internet Access container *****"
CreateTunnelAdapter
ConfigureAuthentication
SetConfigFile
EnableLogging
PreTunnelFirewallRules
StartOpenVPN
PostTunnelFirewallRules