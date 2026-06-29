---
title: "Building a Simple AWS Virtual Appliance with FortiGate and Gateway Load Balancer"
date: 2026-06-29T10:00:00+02:00
draft: false
tags: ["AWS", "GWLB", "FortiGate", "Terraform", "Networking", "Geneve", "CloudSecurity"]
categories: ["AWS", "Networking"]
---

# Building a Simple AWS Virtual Appliance with FortiGate and Gateway Load Balancer

After exploring a plain Linux-based transparent appliance with AWS **Gateway Load Balancer (GWLB)** and GENEVE, I wanted to test a more production-like security appliance. FortiGate (Fortinet's virtual NGFW) was the natural next step.

This is a continuation of the series. You can find the first article here:  
[Building a Simple AWS Virtual Appliance with Gateway Load Balancer](https://mplexia.com/posts/building-a-simple-aws-virtual-appliance-with-gateway-load-balancer/)

Full Terraform code:  
[https://github.com/lrozehnal/aws_virtual_appliances_tests/tree/master/03-simple-using-fortigate](https://github.com/lrozehnal/aws_virtual_appliances_tests/tree/master/03-simple-using-fortigate)

## Why FortiGate with GWLB?

GWLB + GENEVE provides a clean, transparent way to insert virtual appliances into your traffic path. FortiGate has native GENEVE support, which makes integration much smoother than building everything manually with Linux tools (`gwlbtun`, `iptables`, etc.).

## Architecture

The setup follows the same pattern as the Linux version:

- **clientVPC**: Contains the client EC2 instance (the one we want to inspect) and the Gateway Load Balancer Endpoint (GWLBe). Multiple subnets and dedicated route tables handle the traffic redirection.
- **inspectVPC**: Hosts the GWLB target group and the FortiGate VM (plus bastion hosts for management access).

Traffic flow:
1. Client EC2 → route table → GWLBe  
2. GWLBe → GWLB (PrivateLink)  
3. GWLB → GENEVE tunnel → FortiGate  
4. FortiGate inspects and returns traffic via GENEVE → GWLB → client

I also added a second FortiGate instance to demonstrate how GWLB can load balance traffic across multiple appliances. I used the 1-ARM FortiGate version, which is sufficient for this test. I quite like the simplicify using the tunnel for returning the tunnel after the inspection to whence it cames. The FortiGate is configured to accept traffic from the GENEVE tunnel and return it back through the same tunnel.

## Deployment with Terraform

The Terraform configuration is structured very similarly to previous scenarios (`networking.tf`, `gwlb.tf`, `ec2.tf`, etc.).

Key highlights:

- Uses the official **FortiGate-VM64-AWSONDEMAND** AMI from AWS Marketplace.
- Instance type: `t3.medium` (adjust based on needs).
- `source_dest_check = false` (required for routing).
- User data template injects the initial FortiGate configuration. I was nicely surprised that FortiGate supports cloud-init style user data, which simplifies the initial setup. Including the changing of the initial password and basic network configuration.
- One of the parametrs required by Fortinet is the remote IP of the GENEVE tunnel. This is passed as a variable to the user data template. Annoyingly this is not part of provided GWLB resource and had to be looked up separately).

### FortiGate User Data (fortinet-userdata.tpl)

```yaml
#cloud-config

config system admin
    edit admin
        set password ${fortinetpassword}
    next
end

config system interface
    edit "port1"
        set alias "GWLB"
        set mode static
        set allowaccess ping https ssh http
        set defaultgw disable
    next
end

config system geneve
    edit "GWLB-GENEVE"
        set interface "port1"
        set type ppp
        set remote-ip ${geneve_remote_ip}
    next
end

config router static
    edit 1
        set dst 0.0.0.0 0.0.0.0
        set device "GWLB-GENEVE"
        set distance 5
    next
end

config firewall policy
    edit 1
        set name "GWLB-In"
        set srcintf "GWLB-GENEVE"
        set dstintf "port1"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
        set logtraffic all
    next
    edit 2
        set name "GWLB-Return"
        set srcintf "port1"
        set dstintf "GWLB-GENEVE"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
    next
    edit 3
        set name "GENEVE-Intra"
        set srcintf "GWLB-GENEVE"
        set dstintf "GWLB-GENEVE"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
    next
end
```

## Packet Flow

The flow is nearly identical to the Linux scenario:

- Outbound traffic from the client is forced through the GWLBe.
- GWLB encapsulates packets in GENEVE and delivers them to FortiGate.
- FortiGate processes the traffic using its firewall policies and routes it back through the GENEVE interface.
- Return traffic follows the symmetric path.

Management access is provided via dedicated bastion instances with public IPs (and optional Route 53 records). Funny enough, there's bastion for accessing client VPC and bastion for accessing inspect VPC. This is because the FortiGate appliance has no public IP and its default route points into the GENEVE tunnel, so you cannot reach it directly from the internet.

## Lessons Learned

- **GENEVE configuration** on FortiGate is straightforward once you get the interface and routing right.
- Keep management traffic separate — bastions are essential when the appliance's default route points into the tunnel.
- Pay attention to MTU (GENEVE overhead) and security group rules.
- This pattern works very well for commercial NGFWs and can be extended with FortiGate features like IPS, application control, VPNs, etc.

## Wrap Up

Replacing the bare Linux appliance with FortiGate shows how powerful and flexible the GWLB + GENEVE pattern really is. You get a full-featured next-generation firewall with minimal custom scripting.

Again, The sky is the limit — you can now easily test more advanced scenarios, auto-scaling target groups, centralized management with FortiManager, or other vendors.

**Repository**: [aws_virtual_appliances_tests](https://github.com/lrozehnal/aws_virtual_appliances_tests)

Happy experimenting! 🚀

*Ludek Rozehnal — AWS Cloud Networking Consultant & Terraform Enthusiast*
