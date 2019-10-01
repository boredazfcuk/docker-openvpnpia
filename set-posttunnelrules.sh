#!/bin/ash

LoadPretunnelRules(){
   echo "$(date '+%c') Load custom post-tunnel rules"
   iptables-restore --noflush < "${CONFIGDIR}/rules.v4.posttunnel"
}