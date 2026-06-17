+++
date = '2026-06-17T18:13:36+02:00'
draft = false
title = 'Building a Simple AWS Virtual Appliance with Gateway Load Balancer'
+++

## Introduction

A few days ago I revisited one of the items on my long-running "todo one day" list — various networking use cases I want to explore but rarely have time for. This time it was AWS GWLB + a simple Linux-based virtual appliance.

## Why this is beneficial

Many networking and security teams need to insert virtual appliances (firewalls, IDS/IPS, WAFs, etc.) into their AWS traffic paths. GWLB makes this much cleaner than traditional methods, but setting it up correctly with proper routing, Geneve encapsulation, and Terraform can be tricky.

## What is GWLB / GENEVE

Gateway Load Balancer (GWLB) is one of the Elastic Load Balancers currently offered by AWS. The other load balancers — Network Load Balancer (NLB) and Application Load Balancer (ALB) — are more generic: NLB operates at L4 (TCP), while ALB operates at L7 (HTTP) with options for TLS/SSL manipulation. Simplified, they are like native HAProxy services in AWS.
GWLB is different. It is not a classic load balancer. Instead, AWS designed it as a transparent network gateway that uses overlay networking (via GENEVE) to route traffic through third-party virtual appliances for inspection or manipulation.
GENEVE (Generic Network Virtualization Encapsulation) is the tunneling/encapsulation protocol defined in RFC 8926. The name is a clever acronym: Generic Network Virtualization Encapsulation. Unlike older protocols such as VXLAN, NVGRE, or GRE, GENEVE was designed from the ground up to be highly extensible. It uses flexible Type-Length-Value (TLV) options that allow carrying rich metadata between tunnel endpoints without breaking the base protocol. This makes it particularly well-suited for modern use cases like AWS Gateway Load Balancer, where additional context (flow information, security tags, etc.) needs to be passed to virtual appliances.

## Scenario

I wanted to go a bit crazy, but decided to start simple.
![Initial](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic1.png)
 The scenario is simple but effective: We have an EC2 instance in a public VPC with a public IP address and full internet access. Our goal is to inspect (or manipulate) its traffic.
To achieve this, we introduce a Linux-based inspection appliance (a plain Amazon Linux EC2 instance) and place an AWS Gateway Load Balancer (GWLB) in front of it. The GWLB acts as the entry point into our overlay network.
To avoid disrupting normal routing inside the client VPC, we expose the GWLB as a Gateway Load Balancer Endpoint (GWLBe) inside the same VPC. We then update the routing so that outbound traffic from the client EC2 is redirected toward this GWLBe. The endpoint forwards the traffic to the GWLB, which encapsulates it using GENEVE and sends it to the inspection appliance.
(As usual — a picture speaks a thousand words.)
![Overall diagram](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic2.png)

 ## Deployment
 
 As usual (because I am a Terraform purist) the scenario is deployed using Terraform. The code is available here: https://github.com/lrozehnal/aws_virtual_appliances_tests/tree/master/01-simples-aws-solution

 ## Solution
 
 Let me start by describing the solution. We deploy two VPCs — a “clientVPC” with the to-be-inspected “client EC2”, and an “inspectVPC” with the “inspect EC2”.
Because routing in AWS is tied to subnets, and we need two different routing behaviors in the clientVPC, we create two subnets in the same AZ: one for the client EC2 and one for the GWLBe. The clientVPC also has an Internet Gateway (IGW) to provide public internet access. The inspectVPC needs only one subnet for the GWLB and inspect EC2 (plus its own IGW for easy remote access).
What makes this setup interesting is the custom routing required for the different subnets (remember, in AWS route tables are tied to subnets).
In the clientVPC there are three distinct route tables:
- The first (for clientEC2) has the default route (0.0.0.0/0) pointing toward the GWLBe instead of the IGW.
- The second (for the GWLBe subnet) has the default route toward the IGW as usual.
- The third (associated with the IGW) routes return traffic (0.0.0.0/0) back through the GWLBe.

 The inspectVPC is straightforward — just a regular VPC with the GWLB and inspect EC2.

![When it's built](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic3.png)
 However what is needed on the inspect EC2 is GENEVE support. There are multiple ways how to make the linux EC2 GENEVE ready - native kernel, openvswitch but in the end I went for AWS GWLB Tunnel handler - https://github.com/aws-samples/aws-gateway-load-balancer-tunnel-handler.git (gwlbtun); generally get the binary, get a script which set up the tunnel interfaces and apply some "rules" - the exact exec is shown here:  https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/01-simples-aws-solution/terraform/inspect-user-data.sh 

 When the gwlbtun service is started, it will introduce two uni-directional tunnels, one tunnel is being used for traffic from GWLB and the other is supposed to be use by the appliance for sending the traffic back to GWLB - so for the most simple scenario, we just to want to confirm all is working as expected, hence we would take whatever comes in via in-tunnel and put in back out via out-tunnel

 In this particular case, there's this line:
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
View link

1) There’s nothing special on the clientEC2 — the server got its IP address and default route configured when provisioned, using the default VPC subnet router (1st IP of the subnet).
2) When the packet hits the VPC subnet router, the first route table is consulted. Because there is a specific default route (0.0.0.0/0) via the GWLBe, the traffic is routed toward it.
3) Traffic between the endpoint and endpoint service is handled as part of AWS PrivateLink. It hits the GWLB endpoint and is delivered to the GWLB.
4) The GWLB has the inspectEC2 registered as the only target, so the traffic is forwarded via the GENEVE tunnel toward the EC2.
5) The inspectEC2 does nothing — it simply copies the packet from the inbound tunnel to the outbound tunnel.
6) The packet is sent back via GENEVE to the GWLB.
7) The GWLB sends the traffic back to the GWLBe via PrivateLink from the inspectVPC to the clientVPC.
8) In the clientVPC, there is a specific route in the route table for the subnet where the GWLBe lives, so the packet is routed toward the clientVPC’s IGW, where it is NATed to the public IP address of the clientEC2. (This is potentially important — even though the packet left the VPC, it is still NATed to the client EC2’s public IP!)

…and that’s it. It might look complicated, but just follow the packet.
For the return traffic:

9) The clientVPC uses its custom route table (for return traffic only) and the return packet is routed toward the GWLBe.
10) The return packet is routed via PrivateLink from the GWLBe to the GWLB.
11) The GWLB sends it via GENEVE to the inspect EC2.
12) The inspect EC2 copies the return packet from the inbound tunnel to the outbound tunnel (note: copy-paste, no IP routing involved).
13) The inspect EC2 sends the return packet via GENEVE back to the GWLB.
14) The GWLB sends the return packet via PrivateLink from the inspectVPC to the GWLBe in the clientVPC.
15) Finally, the GWLBe, using the local VPC route, sends the packet back to the client EC2.

…and again, it just works.



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
The TCP dump shows the 1st packet arriving via the inbound tunnel (gwi interface) and being sent back via the outbound tunnel (gwo interface), and similarly for the reply. No routing is involved on the inspectEC2.
I also tried a bit of filtering with tc (traffic control as part of Linux’s iproute2) as I had never done it before, but let’s be honest, it’s not very user-friendly. The following is part of the script used by gwlbtun:  https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/02-simple-aws-solution-and-very-simple-filter/terraform/inspect-user-data.sh 
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

In the previous scenario, it’s demonstrated that GENEVE actually works on EC2. But to be honest, without iptables and routing it’s a bit useless (in my personal opinion). I could introduce Linux namespaces to separate management access from routing for those tunnels, but let’s not overcomplicate it for now.
I changed the default route on the inspectEC2 to point toward the outbound GENEVE tunnel, so everything is automatically routed back via the GWLB. Because I lose direct management access, I added another EC2 (a bastion) next to the inspectEC2. I also added a Squid HTTP proxy on the bastion and redirect HTTP/HTTPS traffic as part of the inspection.
![iptables and proxy](/images/posts/Building-a-Simple-AWS-Virtual-Appliance-with-Gateway-Load-Balancer/pic5.png)
This turned out to be surprisingly straightforward. We already know how to handle GENEVE and GWLB/GWLBe, so we just needed to adjust the script that runs when gwlbtun starts:  - https://github.com/lrozehnal/aws_virtual_appliances_tests/blob/master/04-simple-aws-solution-and-routing-and-iptables/terraform/inspect-user-data.sh.tpl
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

That’s it. I wanted to block something to see the regular iptables firewall actually work (this is from outside to EC2 on port 80):
```bash
# === BLOCK PORT 80 inbound ===
iptables -A FORWARD -i "$IN_IFACE" -p tcp -d 10.1.0.0/24 --dport 80 -j DROP
```

Then I wanted to take any traffic from the clientVPC (where the client/to-be-inspected EC2 lives) on port 80/443 and forward it to my bastionEC2 on port 3128 where Squid listens:
```bash
iptables -t nat -A PREROUTING -i "$IN_IFACE" -s 10.1.0.0/24 -p tcp --dport 80 -j DNAT --to-destination $BASTION_IP:3128
iptables -t nat -A PREROUTING -i "$IN_IFACE"  -s 10.1.0.0/24 -p tcp --dport 443 -j DNAT --to-destination $BASTION_IP:3128
```
And PAT (change the source IP) to the IP address of the inspectEC2:
```bash
iptables -t nat -A POSTROUTING -d $BASTION_IP -p tcp --dport 3128 -j MASQUERADE
```

And it works super nicely. I also wanted to run Squid directly on the inspectEC2 in transparent mode, but I had trouble with return traffic back via GENEVE, so that’s another item for my “todo one day” list (transparent Squid proxy behind GENEVE).

## WRAP UP

This was a fun and educational exercise. What started as a simple “let’s pass traffic through an EC2 instance” quickly turned into a deeper understanding of how AWS Gateway Load Balancer, GENEVE encapsulation, routing, and iptables work together in real life.

Key Takeaways
- GWLB + GENEVE is a powerful and clean way to insert virtual network appliances into your traffic path without massive re-architecture.
- Terraform makes these setups reproducible and version-controlled — highly recommended.
- Even a “simple” pass-through scenario requires careful attention to routing tables, MTU(potentially), and tunnel interfaces.
- Adding real inspection (iptables filtering, proxying, etc.) is straightforward once the base GENEVE tunnel works as it seems 'sky is the limit'

The code for this series is available here: https://github.com/lrozehnal/aws_virtual_appliances_tests 

If you’re working with AWS networking, security appliances, or just want to better understand overlay/underlay architectures, feel free to check out the repo and let me know your thoughts or questions.
Happy experimenting! 🚀

