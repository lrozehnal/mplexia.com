+++
date = '2026-05-11T12:31:04+02:00'
draft = true
title = 'Multicast and Aws'
tags = ["socat", "networking", "tcp", "udp", "linux","multicast","hybrid cloud","aws"]
description = "putting things together socat - aws - multicast "
+++

## Introduction

One of the most persistent headaches in modern cloud networking is multicast traffic — especially when you’re operating in hybrid or multi-region AWS environments. What used to be just fencier broadcast in on-premise network (broadcasting is the second nature of LAN swtiches) becomes a nightmare when you try to extend it to the cloud which tend to be more unicast-centric  / SDN by its nature.
You’ve got rock-solid multicast applications running on-premise (market data feeds, trading platforms, media streaming, monitoring systems) basically since the dawn of time and then you start migrating workloads to AWS. Suddenly the multicast packets stop flowing. Or you need to bridge multicast between two AWS regions connected via Transit Gateway peering.
Native AWS Transit Gateway (TGW) multicast domains are great when everything stays inside a single TGW and single region… but the moment you introduce Direct Connect, Site-to-Site VPN, inter-region peering, or hybrid connectivity, the limitations become obvious.
Back in 2025, we faced exactly this problem across several AWS regions and on-premise data centres. Which solution is the right? How completex / difficult to implement? What if I need something  immediately? After evaluating heavy solutions (FRR, Bird, dedicated virtual routers), there's this one ridiculously lightweight tool that did the job perfectly: socat.

## The Multicast Challenge in AWS & Hybrid Environments

AWS Transit Gateway multicast works beautifully within a single multicast domain attached to VPCs in the same region. It acts as a native multicast router, supports IGMP, and scales nicely for intra-VPC or multi-VPC use cases. Correction: The multicast in NOT enabled by default and it CAN NOT be enabled - the TGW has to be pre-provissioned with multicast support - and re-provissioning of TGW could be HUGE problem itself - especially if there are multiple attachments all over the place (I've been there). However, the following scenarios still require workarounds:
- Multicast traffic originating on-premise needing to reach AWS receivers (via Direct Connect or VPN)
- Bridging multicast between multiple AWS regions connected by TGW inter-region peering
- Extending multicast to remote sites or edge locations without native multicast support
- Integrating legacy multicast applications with modern cloud-native services

AWS itself notes that TGW multicast may not be suitable for high-frequency trading or performance-sensitive applications and has strict quotas.

## Why Native Solutions Often Fall Short
- TGW multicast domains do not natively propagate across inter-region peering or hybrid attachments in all configurations. 
- Heavy alternatives add cost, complexity, and operational overhead. 
so here comes the socat solution described in my previous post [Multicast with socat](http://mplexia.com/posts/003-socat-and-multicast/)

## Socat to save

I don't want to repeat myself: basically the first instance of socat translate the incomming multicast to unicast and sent it over multicast-not-supporting network to to the second socat intance where the unicast is translated back to multicast and the receiver can conjest it as usual. It is a simple, elegant, and cost-effective solution that can be deployed quickly without needing complex routing protocols or additional infrastructure.
