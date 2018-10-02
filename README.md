manage_vxlan.sh 
===================================

manage_vxlan.sh is a `bash` script to create vxlan interfaces and networks using unicast.

Why does this script exist?
------------------------

Many public clouds (GCP,AWS,Azure) and hosting providers do not support broadcast or multicast traffic.  Vxlan (rfc7348) can be used to create an overlay network that supports broadcast and multicast in these cloud environments.

Usage
----
```bash
# ./manage_vxlan.sh 

usage: ./manage_vxlan.sh vxint# vxid# "peer list" excidr incidr ifroute mccidr

vxint#  - name of the vxlan interface you want to use (ex: vxlan0)
vxid#   - unique vxlan id number (ex: 101)
mypeers - list of peers OR the word discover to find peers excidr (ex: "1.2.3.4 1.2.3.5")
excidr  - cidr of 'physical' interface to search for peers (ex: 10.11.12.0/24)
          this is required so that we can support more than just a /24
          we only support /24 or smaller (down to /30) right now though :(
incidr  - cidr of vxlan interface you want to use (ex: 192.168.1.0/24)
ifroute - use the interface of the device that can route to this address (ex: 1.1.1.1)
mccidr  - cidr of multicast network to route over this vxlan (ex: 224.0.0.0/4)

```

Requirements
-------

- firewall rules to allow traffic between peers
  - icmp for discovery
  - udp 8472
- the `fping` command (https://fping.org/)
  - apt-get install fping
  - yum install fping
- the `grepcidr` command (http://www.pc-tools.net/unix/grepcidr/)
  - apt-get install grepcidr
  - yum install grepcidr

How to use it
-------

The script can be run manually, thrown into an init script, or added to crontab.  If added to crontab with the `discover` arg it will automatically add new peers found in the `excidr` subnet.

Here are some examples:

The following will:
- create the vxlan0 interface with id 101
- in the 192.168.1.0/24 network
- statically route 224.0.0.0/4
- use the interface that routes to 1.1.1.1
- assign vxlan0 ip in 192.168.1.0/24 that matches the last octet of the interface routing to 1.1.1.1

```bash
# ./manage_vxlan.sh vxlan0 101 "10.1.1.2 10.1.1.3 10.1.1.4" 10.1.1.0/24 192.168.1.0/24 1.1.1.1 224.0.0.0/4
INFO - ip link add vxlan0 type vxlan id 1 dstport 0 local 10.1.1.1 ttl 16 dev eth0
INFO - ip addr add 192.168.1.1/24 dev vxlan0
INFO - ip link set vxlan0 up
INFO - ip route add 224.0.1.0/4 dev vxlan0
INFO - adding new peer: 10.1.1.2
INFO - adding new peer: 10.1.1.3
INFO - adding new peer: 10.1.1.4
```

The following does the same as above but uses discovery (this one is great for cron):
- same as above but runs an fping in 10.1.1.0/24 to search for peers

```bash
# ./manage_vxlan.sh vxlan0 101 discover 10.1.1.0/24 192.168.1.0/24 1.1.1.1 224.0.0.0/4
INFO - ip link add vxlan0 type vxlan id 1 dstport 0 local 10.1.1.1 ttl 16 dev eth0
INFO - ip addr add 192.168.1.1/24 dev vxlan0
INFO - ip link set vxlan0 up
INFO - ip route add 224.0.1.0/4 dev vxlan0
INFO - adding new peer: 10.1.1.2
INFO - adding new peer: 10.1.1.3
INFO - adding new peer: 10.1.1.4
```

Notes and Limitations
-----

- Only supports /24 or smaller (/30 -> /24) subnets for `excidr` peers
  - defining `excidr` allows you to chop up the /24 network
- Only supports adding one static route to the vxlan network
  - others can be added manually


References
------------

- the vxlan RFC: https://tools.ietf.org/html/rfc7348
- the vxlan code: https://github.com/torvalds/linux/blob/master/drivers/net/vxlan.c
- great overview of vxlan on linux: https://vincent.bernat.ch/en/blog/2017-vxlan-linux

License
-------

This work is released under the Mozilla Public License 2.0.  See
[LICENSE](LICENSE) at the root of this repository.
