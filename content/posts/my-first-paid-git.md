+++
date = '2026-06-23T10:53:02+02:00'
draft = false
title = 'My First Paid Gig as an Independent Contractor – Solving Global AWS Connectivity'
+++

A few weeks ago I landed my first paid job as an independent contractor. Nothing huge, but it felt great — and it was a very typical real-world AWS networking challenge.

## The Problem
I got in touch with a former colleague whose team was struggling with onboarding a new data partner. Their environment was in ap-southeast-2 (APAC), while the partner was sending data from the New York area (us-east-1).
They had initially set up TCP connect using stunnel over the public internet. With ~200 ms latency and occasional jitter, it was causing serious issues for their workload.
They remembered I had solved similar cases before and asked for help.
So we had three parties: data provider in the US, data consumer in APAC, and me sitting in Europe — time for some global connectivity!

## Requirements & Constraints
After the initial call we agreed on the key constraints:

- The client was using Terraform, but their Production and UAT environments were strictly separated — two completely independent Terraform deployments. They wanted to keep it that way.
- The data provider could offer either:
- - Direct Connect with Virtual Interfaces + BGP, or
- - A shared AWS Direct Connect Gateway (DXGW).
- The client was not using Transit Gateway (TGW) and was hesitant to introduce one across their environments.

## The Proposed Solution
I suggested (and later demoed) a clean solution using AWS PrivateLink:

- Create a dedicated VPC attached to a Transit Gateway (as requested by the data provider).
- Place a Network Load Balancer (NLB) in that VPC and expose it as a PrivateLink Endpoint Service.
- The client would then create VPC Endpoints inside their Production and UAT VPCs to consume the data.

Benefits of this approach:

- Production and UAT stay completely isolated.
- The client’s VPCs remain fully isolated from the data provider’s network (no shared blast radius).
- No need to overhaul their existing networking.

## Where to Place the Endpoint Service?
This was the interesting part. We had three options:

- Put everything in us-east-1 (closest to the data provider)
- Put everything in ap-southeast-2 (closest to the consumer)
- Put the Endpoint Service in us-west-1 (geographically in the middle)

I decided to test it.

## The Test
I built a small test environment with the data provider in us-east-1, the consumer in ap-southeast-2, and PrivateLink Endpoint Services in multiple regions (us-east-1, us-west-1, ap-southeast-2, and even ap-southeast-1).
I used tools like hping3, curl, and Locust (which turned out to be excellent — more on that later) to measure performance.
Result: Latency was almost identical (~205 ms) no matter where I placed the NLB/Endpoint Service. The AWS backbone handled the traffic very consistently.
While this was just a short test, the initial results were very promising and significantly more stable than the original IPSec VPN over the public internet.
In the end, the client decided to deploy the Endpoint Service in ap-southeast-2 (closest to their environment). Thanks to Terraform, the solution is very flexible — if they ever want to move the Endpoint Service to another region, they can do so with minimal effort.

## The Feedback
The feedback was immediate and very positive.
After running the data feed in UAT for a few weeks, the client performed a seamless cutover to the new solution. They simply added the new PrivateLink target for the data feed.
Their end customer quickly reported a significant improvement in overall performance — much more stable throughput with no more "hangs" or interruptions.
Everyone involved was happy with the outcome.

## Wrap Up & Call to Action
This was a great reminder that even “standard” connectivity challenges can have elegant, low-risk solutions when you combine the right AWS services.
If you’re facing similar global connectivity, cross-region data ingestion, Direct Connect, or PrivateLink challenges — feel free to reach out. I’m always happy to have a short discovery call and see how I can help.
Test code: https://github.com/lrozehnal/AWSdelay
Happy experimenting! 🚀