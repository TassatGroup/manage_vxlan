#!/bin/bash
#
# setup and or update a vxlan on this machine
#
if [ $# -ne 7 ];then
  echo
  echo "usage: $0 vxint# vxid# \"peer list\" excidr incidr ifroute mccidr"
  echo
  echo "vxint#  - name of the vxlan interface you want to use (ex: vxlan0)"
  echo "vxid#   - unique vxlan id number (ex: 101)"
  echo "mypeers - list of peers OR the word discover to find peers excidr (ex: \"1.2.3.4 1.2.3.5\")"
  echo "excidr  - cidr of 'physical' interface to search for peers (ex: 10.11.12.0/24)"
  echo "          this is required so that we can support more than just a /24"
  echo "          we only support /24 or smaller (down to /30) right now though :("
  echo "incidr  - cidr of vxlan interface you want to use (ex: 192.168.1.0/24)"
  echo "ifroute - use the interface of the device that can route to this address (ex: 1.1.1.1)"
  echo "mccidr  - cidr of multicast network to route over this vxlan (ex: 224.0.0.0/4)"
  echo
  echo "example: $0 vxlan0 101 discover 10.11.12.0/24 192.168.1.0/24 1.1.1.1 224.0.0.0/4"
  echo
  echo "INFO - you must have the fping and grepcidr commands installed"
  echo
  exit 1
fi

# check for stuff we need
[ ! `which fping` ] && echo "ERROR - this script requires the fping command" && exit 1
[ ! `which grepcidr` ] && echo "ERROR - this script requires the grepcidr command" && exit 1

# set and check vars
myvxin=$1
myvxid=$2
mypeers=$3
excidr=$4

# grab the external cidr prefix and print if within supported range
excidrpre=$(echo ${excidr}|awk -F/ '{print $NF}'|awk '$1>=24 && $1<=30')
# exit if not supported
[ -z ${excidrpre} ] && echo "ERROR - unsupported exteral cider prefix: ${excidr}" && exit 1

incidr=$5
ifroute=$6
mccidr=$7

# let's make sure the cidrs are valid
checkcidr=$(grepcidr -e "${excidr} ${incidr} ${mccidr}" /dev/null 2>&1 >/dev/null)
[[ "${checkcidr}" = *"Not a valid"* ]] && echo "ERROR: excidr:${excidr} incider:${incidr} mccidr:${mccidr} invalid" && exit 1

# get ip of interface with requested route
myip=$(ip route get ${ifroute} | grep -oP 'src \K\S+')

# get last octet of ip
myoctet=$(echo ${myip}|awk -F. '{print $NF}')

# get name of interface with requested route
myin=$(ip route get ${ifroute} | grep -oP '(?<=dev).*(?=src)'|sed -e 's/\s//g')

# split vars to get some values for later
myinnet=$(echo ${incidr}|awk -F. '{print $1 "." $2 "." $3}')
myinpre=$(echo ${incidr}|awk -F/ '{print $NF}')

# create vxlan interface if it doesn't exist
ip addr show|grep -q -w ${myvxin}
if [ $? -ne 0 ]; then

  # check to see if the vxlan id exists
  ip -d link show|grep 'vxlan id'|awk '{print $3}'|grep -q ${myvxid}
  [ $? -eq 0 ] && echo "ERROR - vxlan id ${myvxid} already exits" && exit 1

  # check to see if the mcast network is already routed
  ip route|grepcidr ${mccidr} > /dev/null 2>&1
  [ $? -eq 0 ] && echo "ERROR - mccidr ${mccidr} already routed here" && exit 1 

  # create vxlan interface 
  echo INFO - ip link add ${myvxin} type vxlan id ${myvxid} dstport 0 local ${myip} ttl 16 dev ${myin}
  ip link add ${myvxin} type vxlan id ${myvxid} local ${myip} dstport 0 ttl 16 dev ${myin}

  # set the ip address of the vxlan to match interface of requested route
  echo INFO - ip addr add ${myinnet}.${myoctet}/${myinpre} dev ${myvxin}
  ip addr add ${myinnet}.${myoctet}/${myinpre} dev ${myvxin}

  # bring the interface up
  echo INFO - ip link set ${myvxin} up
  ip link set ${myvxin} up

  # add mccidr route to ${myvxin} interface
  echo INFO - ip route add ${mccidr} dev ${myvxin}
  ip route add ${mccidr} dev ${myvxin}

fi

# if keyword discover, find peers using fping excluding my own ip
if [ "$mypeers" == "discover" ]; then
  mypeers=$(fping -i 10 -A -a -g ${excidr} |awk 'BEGIN{ORS=" "}1')
fi

# add the peers
for peer in ${mypeers}
do
  # skip adding yourself 
  [ "${peer}" == "${myip}" ] && continue
  # construct the vxlan address of the peer
  #peeroct=$(echo ${peer}|awk -F. '{print $NF}')
  #inpeer=${myinnet}.${peeroct}
  # skip adding a peer that already exists on this ${myvxin} interface
  bridge fdb show dev ${myvxin} | grep -q -w ${peer} |grep '00:00:00:00:00:00' && continue
  echo "INFO - adding new peer: ${peer}"
  bridge fdb append 00:00:00:00:00:00 dev ${myvxin} dst ${peer}
  # quick ping check -- this won't work if other peers havent discovered this peer
  #ping -c 3 ${inpeer}
done

# this is great to log which peers are available
for ip in `fping -i 10 -A -a -q -g ${incidr}`;
do
  echo "[INFO] - $0 able to ping peer ${ip}"
done
