+++
date = '2026-05-05T18:41:54+02:00'
draft = false
title = 'I wanted but .... socat - introduction'
description = "introduction to socat"
tags = ["socat","tcp/ip"]

private = true
unlisted = true
[build]
  list = 'never'

# Extra protection from search engines
noindex = true
robots = "noindex, nofollow"
+++

## I Wanted but ....
Today I really wanted to talk about cool things but as I was thinking about this (next) topic I realised I need to address the elephant in the room first. TCP/IP ... it is a wonderful thing, but I am afraid it is often overcomplicated. TCP connection is like a phone call. You dial, you connect, you talk & listen, you hang up. Simple. But in the world of networking, we often make it more complex than it needs to be. But I'd like to ignore the unnecessary complexity and focus on talking and listening ... like applications do...

## When applications talk to each other
When an application wants to talk to another application, it opens a TCP connection, get so called 'socket' and just write (talks) or read (listen) to/from it. If we ignore the comlexity of TCP/IP, it' just like that - open phone call - both side sent same (steam of) data and the other side reads it and vice-versa. Simple, right? It's just like a pair of unix pipes - over network. 

## Copying a file
If I want to copy a file, I can easily do something like this:
```
cp file1 file2
```
if I want to use pipes, I can do
```
cat file1 > file2
```
but what if I want to do something like
```
cp file1@localhost file2@remotehost
```
using TCP like a pipe e.g.
```
cat file1@localhost > MAGIC_PIPE_OVER_TCP > file2@remotehost
``` 

This is where socat comes in. It is a tool that allows you to create TCP(or UDP) connections and use it ... somewhat


## Socat-way
Using the copy-a-file example, there's nothing stopping us from doing something like this:
- prepare the listening side (get ready to receive a phone call) on the 'server side'
```
(remotehost)# socat TCP-LISTEN:12345,fork,reuseaddr - > file2
```
- then on the 'client side' we can do
```
(localhost)# cat file1 | socat - TCP:remotehost:12345
```

Let's try:
### copy the file using socat
- get the file
```
lab@localhost:~$ 
lab@localhost:~$ echo "this is something I want to copy over" > file1
lab@localhost:~$ 
```
- prepare the receiving side
```
lab@remotehost:~$ 
lab@remotehost:~$ 
lab@remotehost:~$ socat TCP-LISTEN:12345 - > file2
```
- sent the file 
```
lab@localhost:~$ 
lab@localhost:~$ cat file1 | socat - TCP:remotehost:12345
```
- check the result
```
lab@remotehost:~$ cat file2 
this is something I want to copy over
lab@remotehost:~$ 
```

easy right? it's like cat file1 > file2 but over TCP. You can also do the same thing with UDP, or even with a serial port. Socat is a very versatile tool that allows you to create all sorts of connections and do all sorts of things with them.

slightly more complicated example - let say I want to use a proxy - a middle man to which I want to connect over UDP and I want the proxy to connect to remotehost via TCP .. and copy the file

Let's do it:
### copy the file using socat over UDP via a proxy
- get new file
```
lab@localhost:~$ 
lab@localhost:~$ echo "this is something completely else" > file9 
```
- prepare the receiving side:
```
lab@remotehost:~$ 
lab@remotehost:~$ socat TCP-LISTEN:12345 - > file7
```
- prepare the proxy - we want to listen on UDP and forward it as TCP, right?
```
lab@proxy:~$
lab@proxy:~$ socat -u UDP-LISTEN:54321,fork TCP:remotehost:12345
```
- and finally send the file - over UDP via the proxy
```
lab@localhost:~$
lab@localhost:~$ cat file9 | socat -u - UDP:proxy:54321
```
- check the result
```
lab@remotehost:~$ cat file7 
this is something completely else
lab@remotehost:~$ 
```
note: the tcp-listen on the receiving side needs to be ctlr+C as the UDP steam has 'no-end' and thus the connection is not closed and the file is not closed and thus the content is not flushed to disk.

### tunneling real world application
The last example would be ssh - it uses tcp port 22 on the server / receiving side and the client connects to it and then the ssh server runs the command and sends the output back to the client. It's like a remote shell over TCP. Can we make it working over UDP?

- prepare the sshd server side
 ```
lab@remotehost:~$
lab@remotehost:~$ socat UDP-L:2222 TCP:localhost:22

 ```
 - prepare the client side - 
```
lab@localhost:~$ 
lab@localhost:~$ socat TCP-L:2222 UDP:remotehost:2222
```
- connect to the localhost of the socat - using localhost:2222
```
lab@localhost:~$ ssh -p2222 localhost
Linux remotehost 6.12.74+deb13+1-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.74-2 (2026-03-08) x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
Last login: Tue May  5 20:56:08 2026 from 10.199.0.1
lab@remotehost:~$ 
```
*SSH OVER UDP!!*
- quick check on the  localhost and remotehost side:
```
lab@localhost:~$ netstat -planu |grep 2222
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
udp        0      0 10.199.0.11:34263       10.199.0.12:2222        ESTABLISHED 112644/socat        
lab@localhost:~$ 
```
```
lab@remotehost:~$ netstat -planu |grep 2222
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
udp        0      0 10.199.0.12:2222        10.199.0.11:34263       ESTABLISHED 109995/socat        
lab@remotehost:~$ 
```
## Why?
Well, I just wanted to demostrate that it doesn't really matter what is using the ~network~ ~tcp~ connection and for what purpose - it's just a bytestream and you can do whatever you want with it. You can use it to copy files, to run remote commands, to forward ports, to create tunnels, to do all sorts of things. Socat is a very powerful tool that allows you to create all sorts of connections and do all sorts of things with them. Bi-directional socket over network. It's like a swiss army knife for network connections. And ultimately for any network applications...

Many other examples are here - http://www.dest-unreach.org/socat/doc/socat.html#EXAMPLES  
and I can promise I will revisit some of those in the future posts.