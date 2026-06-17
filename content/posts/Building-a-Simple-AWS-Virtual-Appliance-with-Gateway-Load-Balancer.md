+++
date = '2026-06-17T18:13:36+02:00'
draft = true
title = 'Building a Simple AWS Virtual Appliance with Gateway Load Balancer'
+++

## Introduction

Few days ago, I revisited one of items in my 'todo one day' where I store various 'usecases' which I'd like to play with but usually I don't have enough of time to play with, but here we go: this time it's a plain EC2 behind AWS GWLB which can somehow 'inspect and /or manipulate' the traffic. Nothing special, just a plain linux-based router....

## Why this is beneficial

Many networking and security teams need to insert virtual appliances (firewalls, IDS/IPS, WAFs, etc.) into their AWS traffic paths. GWLB makes this much cleaner than traditional methods, but setting it up correctly with proper routing, Geneve encapsulation, and Terraform can be tricky.

## What is GWLB / GENEVE

Gateway loadbalancer is one of Elastic Load Balancers (ELB) currently offered by AWS. The other load balancers - network (NLB) and application (ALB) are generic loadbalancer - nlb operates on L4 / TCP while alb operates on L7/HTTP plus there's certain option for manipulation of TLS/SSL  (so one can easily apply various modes as needed e.g. TLS offload for web servers) . Simplified, it's just a haproxy in AWS as native service.
GWLB is different - it's not a classic "loadbalancer" - it's rather a way how AWS introduce network gateway for network virtualization or overlay network architecture in order to allow utilizing 3rd party appliances. To put it bluntly, it is what you have to do if you want to take a network traffic in one part of the network and bring it an appliance to inspect it.

GENEVE is tunneling (or encapsulation) method defined under https://datatracker.ietf.org/doc/html/rfc8926 ; The name is a clever acronym: **Ge**neric **Ne**twork **V**irtualization **E**ncapsulation -> GENEVE. Unlike older protocols such as VXLAN, NVGRE, or GRE, GENEVE was designed from the ground up to be highly extensible. It uses flexible Type-Length-Value (TLV) options that allow carrying rich metadata between tunnel endpoints without breaking the base protocol. This makes it particularly well-suited for modern use cases like AWS Gateway Load Balancer (GWLB), where additional context (flow information, security tags, etc.) needs to be passed to virtual appliances.

## Scenario

I wanted to go bit crazy but let's start with something super simple:
![Initial](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic1.png)
 there's EC2 instace in public VPC (the EC2 instance has a public IP address assiged and full access to and from the public internet) and we want to inspect the traffic. The way how this is done is fairly straight-forward - we need to introduce the 'inspection' appliance (I am going to use plain Amazon Linux EC2), and put GWLB in front of this EC2 - the GWLB will work as the 'entry point' into our 'overlay'; Additionaly, as we don't want to impact overall routing within our to-be-inspected VPC / EC2, we are going to present the GWLB (which lives next to the appliance) as GWLB endpoint (GWLBe) within the to-be-inspected VPC, and we would just re-route traffic from EC2 toward GWLBe which would bring it to GWLB where the traffic is sent via GENEVE to our inspection appliacnce... fortunately a picture speaks thousand words 
![Overall diagram](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic2.png)

 ## Deployment
 
 As usual (because I am a terraform ~nazi~ purist) the scenario is deployed using terraform , the code is here: https://github.com/lrozehnal/aws_virtual_appliances_tests/tree/master/01-simples-aws-solution ;

 ## Solution
 
 Let me start by describing the solution - we are going to deploy two VPC - first  "clientVPC" with to-be-inspected "client EC2", and second  "inspect VPC" with  "inspect EC2". As the routing in AWS is tied to subnets (and we would need two different types of routing in clientVPC), we need to introduce two different subnet (in/ for the same AZ) - one for clientEC2 and other for GWLBe. Also there's internet gateway (igw) in clientVPC in order to make it public cloud with an access to public internet.  In "inspectVPC" we need just one subnet for GWLB and inspectEC2. There's also igw for simplyfing the remote access ... 
 What slightly out of regular is routing for those individual subnets (remember, in AWS route-tables are tied to subnets and viceversa).
 In the clientVPC, there will be three distinquish route-tables:
 The first subnet/route-table with "clientEC2" - it won't have default route towards local igw, but towards GWLBe(!) 
 The second subnet/route-table where gwlbe lives would have default route towards igw as usual.
 The third route-table present at clientVPC  is for igw (!)  in here it has to be specified, that the 0.0.0.0/0 (for return traffic) lives behind the gwlbe. (default route on igw towards gwlbe looks wild, but it impacts only return traffic, not the outbound)
 There's nothing special within the other VPC... just a regular VPC with GWLB and inspect EC2 (the 3rd appliance)
![When it's built](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic3.png)
 However what is needed on the inspect EC2 is GENEVE support. There are multiple ways how to make the linux EC2 GENEVE ready - native kernel, openvswitch but in the end I went for AWS GWLB Tunnel handler - https://github.com/aws-samples/aws-gateway-load-balancer-tunnel-handler.git (gwlbtun); generally get the binary, get a script which set up the tunnel interfaces and apply some "rules" - the exact exec is shown here:  https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/01-simples-aws-solution/terraform/inspect-user-data.sh 

 When the gwlbtun service is started, it will introduce two uni-directional tunnels, one tunnel is being used for traffic from GWLB and the other is supposed to be use by the appliance for sending the traffic back to GWLB - so for the most simple scenario, we just to want to confirm all is working as expected, hence we would take whatever comes in via in-tunnel and put in back out via out-tunnel

 In this partucular case, there's this line:
 ```bash
 tc filter add dev "$2" parent ffff: protocol all prio 2 u32 match u32 0 0 flowid 1:1 action mirred egress mirror dev "$3"
 ```

```bash
[ec2-user@ip-10-2-0-11 ~]$ ip a |grep mtu
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
4: gwi-g4NXKSgMgMK: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 8500 qdisc mq state UNKNOWN group default qlen 500
5: gwo-g4NXKSgMgMK: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 8500 qdisc mq state UNKNOWN group default qlen 500
[ec2-user@ip-10-2-0-11 ~]$ 
```

and it just works! 

Let's follow the packet:
![Follow the packet](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic4.png)
1) there's nothing special on clientEC2 - the server got its IP address and default route configured when provissioned, using default VPC/subnet router (1st ip of the subnet)
2) when the packet hits the vpc/subnet router, the 1st route-table is consulted - as there's specific route for 0.0.0.0/0 via gwlbe, the traffic is routed towards it
3) well, traffic between endpoint and endpoint service is routed as part of AWS private link - it hits the GWLB endpoint and somehow popped up from the GWLB
4) GWLB has inspectEC2 registered as the only target and hence the traffic is forwarded via the GENEVE tunnel towards EC2
5) the inspectEC2 does nothing , plainly copy the packet from the inbound tunnel into outbound tunnel ... 
6) ... and hence it will sent it back via GENEVE to GWLB 
7) GWLB sent the traffic back to GWLBe via private link from InspectVPC to ClientVPC
8) in ClientVPC, there's specific route within route-table for a subnet where GWLBe lives and therefore the packet is routed towars clientVPC's igw where the traffic is NAT'ed to publicIP address of the clientEC2 (!! this is potentially important - even though the packet left the VPC, the packet is still NAT'ed to public IP address of the clientEC!!)

... and that's it - it might look  bit complicated but ... just follow the packet

For the return traffic
9) the clientVPC uses it's custom route-table (it's for this return traffic only) and the return packet is routed toward GWLBe
10)  the return packet is routed via privatelink from GWLBe to GWLB
11)  GWLB sent it via GENEVE to inspect EC2
12)  the inspect EC2 copy the return packet from inbound tunnel to outbound tunnel (note it's copy-paste, no ip routing is involved)
13)  and the inspect EC2 sent return packet via GENEVE back to GWLB
14)  GWLB sent the return packet via privatelink from InspectVPC to  GWLBe in ClientVPC
15)  and finally, the GWLBe, using the local VPC route sents the packet back to EC2

and again, it just works


```bash
[ec2-user@ip-10-2-0-11 ~]$ ip addr show | grep -E "inet|mtu" |grep -v "inet6"
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
2: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc mq state UP group default qlen 1000
    inet 10.2.0.11/27 metric 512 brd 10.2.0.31 scope global dynamic ens5
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
4: gwi-g4NXKSgMgMK: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 8500 qdisc mq state UNKNOWN group default qlen 500
5: gwo-g4NXKSgMgMK: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 8500 qdisc mq state UNKNOWN group default qlen 500
[ec2-user@ip-10-2-0-11 ~]$ 
[ec2-user@ip-10-2-0-11 ~]$ ip route
default via 10.2.0.1 dev ens5 proto dhcp src 10.2.0.11 metric 512 
10.2.0.0/27 dev ens5 proto kernel scope link src 10.2.0.11 metric 512 
10.2.0.1 dev ens5 proto dhcp scope link src 10.2.0.11 metric 512 
10.2.0.2 dev ens5 proto dhcp scope link src 10.2.0.11 metric 512 
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown 
[ec2-user@ip-10-2-0-11 ~]$ 
[ec2-user@ip-10-2-0-11 ~]$ sudo tcpdump -i any icmp -nn -v
tcpdump: data link type LINUX_SLL2
dropped privs to tcpdump
tcpdump: listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
17:57:17.869692 gwi-g4NXKSgMgMK In  IP (tos 0x0, ttl 53, id 25743, offset 0, flags [none], proto ICMP (1), length 84)
    188.92.253.109 > 10.1.0.24: ICMP echo request, id 52242, seq 364, length 64
17:57:17.869703 gwo-g4NXKSgMgMK Out IP (tos 0x0, ttl 53, id 25743, offset 0, flags [none], proto ICMP (1), length 84)
    188.92.253.109 > 10.1.0.24: ICMP echo request, id 52242, seq 364, length 64
17:57:17.870208 gwi-g4NXKSgMgMK In  IP (tos 0x0, ttl 126, id 20076, offset 0, flags [none], proto ICMP (1), length 84)
    10.1.0.24 > 188.92.253.109: ICMP echo reply, id 52242, seq 364, length 64
17:57:17.870212 gwo-g4NXKSgMgMK Out IP (tos 0x0, ttl 126, id 20076, offset 0, flags [none], proto ICMP (1), length 84)
    10.1.0.24 > 188.92.253.109: ICMP echo reply, id 52242, seq 364, length 64
^C
4 packets captured
5 packets received by filter
0 packets dropped by kernel
[ec2-user@ip-10-2-0-11 ~]$ 

```
the TCP dump shows the 1st packet in via in-tunnel(gwi-interface) and sending the same packet (2nd) back via out-tunnel(gwi-interface)
 (sa: 188.92.253.109 da: 10.1.0.24)
followed by a reply - 3rd packet come in form in-tunnel(gwi-interface) followed by 4th packet (the same as 3rd) leaving via out-tunnel (gwo interface) (sa: 10.1.0.24 da: 188.92.253.109);  No routing on inspectEC2 involved. 

I also tried to do a bit of filtering in 'tc' (traffic control as part of linux's iproute2) as I never done it before but let's be honest, it's not very user friendy:) (following is part of script used by gwlbtun ) https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/02-simple-aws-solution-and-very-simple-filter/terraform/inspect-user-data.sh 
```bash

# Drop TCP port 80
tc filter add dev "$2" parent ffff: protocol ip prio 1 u32 \
  match ip protocol 6 0xff \
  match ip dport 80 0xffff \
  action drop

# Mirror the rest
tc filter add dev "$2" parent ffff: protocol all prio 2 u32 match u32 0 0 flowid 1:1 action mirred egress mirror dev "$3"

```


## Let's use iptables and actually route the traffic

In previous scenario, it's demontrated that GENEVE actually works on EC2 but to be honest, without iptables and routing it's bit useless (my personal opinion)  I guess I can introduce linux namespaces to separate management (regular admin access) with routing for those tunnels... but let's not overcomplicate it ... I am going to change the default route on inspectEC2 to point towards the outbound GENEVE tunnel hence 'everything' will be automatically assumed to be routed back via GWLB.  As I am losing the management access, I need to put another EC2 - a bastion next to inspectEC2 to get myself and access back to inspectEC2 and additionally, I'd like to add squid http proxy on this bastionEC2 and redirect the http/https traffic as part of the inspection.
![iptables and proxy](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic5.png)
This is surprisingly more straightforward - as we already have / know how to deal with implemantaion of GENEVE and GWLB/GWLBe. we just need to tackle the script which is executed when the gwlbtun is started  - https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/04-simple-aws-solution-and-routing-and-iptables/terraform/inspect-user-data.sh.tpl
```bash

# === iptables - SAFE VERSION ===
echo "==> Applying safe iptables rules..."

# Flush rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Allow SSH from anywhere first (critical!)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Default policies - INPUT stays ACCEPT for management
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# === BLOCK PORT 80 inbound ===
iptables -A FORWARD -i "$IN_IFACE" -p tcp -d 10.1.0.0/24 --dport 80 -j DROP

# === forward traffic via squid proxy ===

# Explicit rule for your client subnet
iptables -t nat -A PREROUTING -i "$IN_IFACE" -s 10.1.0.0/24 -p tcp --dport 80 -j DNAT --to-destination $BASTION_IP:3128
iptables -t nat -A PREROUTING -i "$IN_IFACE"  -s 10.1.0.0/24 -p tcp --dport 443 -j DNAT --to-destination $BASTION_IP:3128
iptables -t nat -A POSTROUTING -d $BASTION_IP -p tcp --dport 3128 -j MASQUERADE

# Allow other forwarded traffic
iptables -A FORWARD -i "$IN_IFACE" -j ACCEPT
iptables -A FORWARD -i "$OUT_IFACE" -j ACCEPT
```

That's it: I want to block something to see the regular iptables firewall actually works: (this is from outside to EC2 on port 80)
```bash
# === BLOCK PORT 80 inbound ===
iptables -A FORWARD -i "$IN_IFACE" -p tcp -d 10.1.0.0/24 --dport 80 -j DROP
```

and then I want to take any traffic from the clientVPC (where client/to-be-inspected EC2 lives) to port 80, are forward it to my bastionEC2 port 3128 where squid listen
```bash
iptables -t nat -A PREROUTING -i "$IN_IFACE" -s 10.1.0.0/24 -p tcp --dport 80 -j DNAT --to-destination $BASTION_IP:3128
iptables -t nat -A PREROUTING -i "$IN_IFACE"  -s 10.1.0.0/24 -p tcp --dport 443 -j DNAT --to-destination $BASTION_IP:3128
```
and PAT it (change the source IP) to IP address of the inspectEC2
```bash
iptables -t nat -A POSTROUTING -d $BASTION_IP -p tcp --dport 3128 -j MASQUERADE
```

And it works super nicely...  I also wanted to run squid directly on inspectEC2 in transparent mode but I had troubles with and return traffic back via GENEVE so, there's another item for my todo-one-day list (transparent squid proxy behind GENEVE) :)


## WRAP UP

This was a fun and educational exercise. What started as a simple “let’s pass traffic through an EC2 instance” quickly turned into a deeper understanding of how AWS Gateway Load Balancer, GENEVE encapsulation, routing, and iptables work together in real life.

Key Takeaways
GWLB + GENEVE is a powerful and clean way to insert virtual network appliances into your traffic path without massive re-architecture.
Terraform makes these setups reproducible and version-controlled — highly recommended.
Even a “simple” pass-through scenario requires careful attention to routing tables, MTU(potentially), and tunnel interfaces.
Adding real inspection (iptables filtering, proxying, etc.) is straightforward once the base GENEVE tunnel works as it seems 'sky is the limit'

The code for this series is available here:
github.com/lrozehnal/aws_virtual_appliances_tests

If you’re working with AWS networking, security appliances, or just want to better understand overlay/underlay architectures, feel free to check out the repo and let me know your thoughts or questions.
Happy experimenting! 🚀

