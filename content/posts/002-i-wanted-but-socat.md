+++
title = "socat: The Swiss Army Knife of Networking"
date = '2026-05-05T19:00:00+02:00'
draft = false
description = "A practical introduction to socat — the swiss army knife for turning TCP/UDP into simple data pipes."
tags = ["socat", "networking", "tcp", "udp", "linux"]

private = true
unlisted = true
[build]
  list = 'never'

# Extra protection from search engines
noindex = true
robots = "noindex, nofollow"
+++


## I Wanted to Talk About Cool Stuff… But First, socat

Today I really wanted to jump into more advanced topics, but I realised I first need to address something fundamental.

**TCP connections are actually very simple.**

Think of them like a phone call:
- You dial → connect
- You talk and listen
- You hang up


Applications basically do the same thing: they open a socket and just read/write data. Everything else (handshakes, retransmissions, congestion control) is handled by the kernel.

But what if we could treat a network connection **exactly like a Unix pipe**?

That’s where **`socat`** comes in.

## socat = `cat` Over the Network

`socat` (short for **SOcket CAT**) lets you create bidirectional byte streams between almost anything: TCP, UDP, files, serial ports, etc.

### Simple File Copy Over TCP

On the **receiving side** (remotehost):

```bash
socat TCP-LISTEN:12345,fork,reuseaddr - > file2
```

On the **sending side** (localhost):
```bash
cat file1 | socat - TCP:remotehost:12345
```

That’s it. You just copied a file over the network as easily as cat file1 > file2.
![simple copy](/images/posts/002-i-wanted-but-socat/Canvas1.png)

### More Advanced: UDP → TCP Proxy

On the **receiving side** (remotehost) - that's the same as previous:

```bash
socat TCP-LISTEN:12345,fork,reuseaddr - > file2
```

On the **proxy** (middleman):

```bash
socat -u UDP-LISTEN:54321,fork TCP:remotehost:12345
```

And finally on the **sending side** (localhost):

```bash
cat file1 | socat -u - UDP:proxy:54321
```

That's it - we just sent the file over UDP and TCP glued together by the TCP-to-UDP proxy.
![copy via tcp-udp proxy](/images/posts/002-i-wanted-but-socat/Canvas2.png)

### Real-World Example: SSH Over UDP

```bash 
# On remotehost (forward UDP 2222 → local SSH)
socat UDP-LISTEN:2222,reuseaddr,fork TCP:localhost:22

# On localhost (forward local TCP 2222 → remote UDP)
socat TCP-LISTEN:2222,reuseaddr,fork UDP:remotehost:2222
```

and then just:
```bash
ssh -p2222 localhost
```
### !SSH OVER UDP! 🎉
![ssh via udp](/images/posts/002-i-wanted-but-socat/Canvas3.png)

## Why This Matters

**`socat`** proves that at the end of the day, most network communication is just streams of bytes. Once you understand that, you can:

- Forward ports creatively
- Build quick proxies and tunnels
- Debug tricky connectivity issues
- Create powerful one-liners

It really is the Swiss Army knife of networking.

Many other official examples:  http://www.dest-unreach.org/socat/doc/socat.html#EXAMPLES   

I’ll be showing more advanced socat use cases in future posts (port forwarding, TLS tunnels, relay chains, etc.).
