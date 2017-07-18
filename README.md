# SIP-ALG-Detector

**IMPORTANT:** *This project is not maintained. It may work today (or not).*

*SIP-ALG-Detector* is an utility to detect routers with SIP ALG enabled. It comes with a client and a server:

* The client is executed in a host into the private LAN.
* The server runs in a server with public IP.

Both the client and the server and written in Ruby language.


## About SIP ALG

Many of today's commercial routers implement SIP ALG, coming with this feature enabled by default.

An ALG (Application-level gateway) understands the protocol used by the specific applications that it supports (in this case SIP) and does a protocol packet-inspection of traffic through it. A NAT router with a built-in SIP ALG can re-write information within the SIP messages (SIP headers and SDP body) making signaling and audio traffic between the client behind NAT and the SIP endpoint possible. While ALG could help in solving NAT related problems, the fact is that most of the routers ALG implementations are wrong and break SIP.

More information about SIP ALG in [Voip-Info.org](http://www.voip-info.org/wiki/view/Routers+SIP+ALG).


## How it works

1. Being in a private LAN, `sip-alg-detector.rb` creates a correct INVITE by getting the private address of the host.
1. The INVITE is sent via UDP and/or TCP to a server (public address) in which `sip-alg-detector-daemon.rb` is running in port 5060.
1. When passing through the LAN router, the INVITE could be modified if ALG SIP is enabled in the router.
1. The request arrives finally to the server which takes the request headers and body and send them back to the client in two responses:
   1. `SIP/2.0 180` containing the request headers encoded in `Base64` as response body ("Content-Type: text/plain").
   1. `SIP/2.0 500` containing the request body encoded in `Base64` as response body ("Content-Type: text/plain").
1. The client get the responses, rebuilds the original request (as arrived to the server) and generates a "diff" between its sent request and the mirrored request received from the server.
1. Possible differences between them are displayed (in case SIP ALG exists).
1. Finally test results are displayed in the screen (UDP test and/or TCP test).


## Usage


### Client

The client side `sip-alg-detector.rb` can be runned in interactive or non-interactive mode (by adding "-n" parameter). In non-interactive mode, the server IP must be provided with the "-si" parameter.

```
Usage mode:    ruby sip-alg-detector.rb [OPTIONS]

  OPTIONS:
    -n               :    Non interactive mode (don't ask for parameters during
                          script execution). Required for other parameters to be
                          used.
    -t (tcp|udp|all) :    Tests to perform (TCP, UDP or both). Default "all".
    -si IP           :    IP of the server where 'sip-alg-detecter-daemon.rb'
                          runs. Default "none" (REQUIRED).
    -sp PORT         :    Port of the server when the daemon runs. Default "5060".
    -lp PORT         :    Local port from which UDP request will be sent. Default
                          "5060".

  Script return code: XY
    X    :    UDP ALG test result
    Y    :    TCP ALG test result

    Values of X/Y:
      1    :    ALG test result => FALSE
      2    :    ALG test result => TRUE
      3    :    ALG test dissabled
      4    :    ALG test failed

    In case of error ("couldn't get local ip/port") the script returns other
    codes (as 1).
```

Built on Ruby with no external dependencies or libraries, the client is supposed to run in Linux, Windows and Mac. However, ruby-readline is required interactive mode to work.


### Server

The server side `sip-alg-detector-daemon.rb` must run in a host with public IP. It's also written in Ruby and requires `daemons` gem installed:

```bash
~# gem install daemons
```

By default it listens in "0.0.0.0:5060" (all the interfaces). The address can be set with "-i" (IP to bind) and "-p" (port to bind).


## Example

* Let's assume we run the server in a host with public IP 99.98.130.199:

```bash
~# ruby sip-alg-detector-daemon.rb -i 99.88.77.66
```

```
Sat Jun 13 22:29:58 2009 INFO: Starting SIP ALG Detector daemon...
Sat Jun 13 22:29:58 2009 INFO: Use '-i IP' to set the listening IP
Sat Jun 13 22:29:58 2009 INFO: Use '-p PORT' to set the listening port
Sat Jun 13 22:29:58 2009 INFO: Bind address: 99.98.130.199:5060
```

* The router has a public IP 66.111.222.111.
* The client host has a private IP 192.168.1.102.
* Then we run the client in interactive mode:

```bash
~# ruby sip-alg-detector.rb
```

```
Settings:
- Test UDP: true
- Test TCP: true
- Server IP: 99.98.130.199
- Server port: 5060
- Local port: 6060

INFO: Starting the SIP UDP ALG test...

DEBUG: Connecting to the server (UDP:99.98.130.199:5060) ...

DEBUG: Sending SipAlgDetectorClient::InviteRequest to the server ...

DEBUG: Sent from 192.168.1.102:6060 to 99.98.130.199:5060:
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
INVITE sip:sip-alg-detector-daemon@99.98.130.199:5060 SIP/2.0
Via: SIP/2.0/UDP 192.168.1.102:6060;rport;branch=z9hG4bKt6gf1sqa
Max-Forwards: 5
To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
From: "SIP ALG Detector" <sip:sip-alg-detector@killing-alg-routers.war>;tag=g15guctc
Call-ID: bggvcdx2d8@192.168.1.102
CSeq: 405 INVITE
Contact: <sip:0123@192.168.1.102:6060;transport=udp>
Allow: INVITE
Content-Type: application/sdp
Content-Length: 252

v=6
o=vpujzk2x 21066632 3068032 IN IP4 192.168.1.102
s=-
c=IN IP4 192.168.1.102
t=0 0
m=audio 4731 RTP/AVP 8 0 3 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:3 GSM/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20
----------------------------------------------------------

DEBUG: Waiting for the responses from the server ...

DEBUG: 1/2 responses received

DEBUG: 2/2 responses received

DEBUG: Mirrored request sent in the response from the server:
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
INVITE sip:sip-alg-detector-daemon@99.98.130.199:5060 SIP/2.0
Via: SIP/2.0/UDP 66.111.222.111:5060;branch=z9hG4bKe7a074d2e0e180b508243c764c661a7e
Via: SIP/2.0/UDP 192.168.1.102:6060;rport;branch=z9hG4bKt6gf1sqa
From: "SIP ALG Detector" <sip:sip-alg-detector@killing-alg-routers.war>;tag=g15guctc
To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
Call-ID: bggvcdx2d8@192.168.1.102
CSeq: 405 INVITE
Contact: <sip:0123@192.168.1.102:6060;transport=udp>
max-forwards: 4
Allow: INVITE
Content-Type: application/sdp
Content-Length:   254

v=6
o=vpujzk2x 21066632 3068032 IN IP4 66.111.222.111
s=-
c=IN IP4 66.111.222.111
t=0 0
m=audio 7070 RTP/AVP 8 0 3 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:3 GSM/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20
----------------------------------------------------------

INFO: There are differences between sent request and received mirrored request:
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--1a2--
Received by server  :  Via: SIP/2.0/UDP 66.111.222.111:5060;branch=z9hG4bKe7a074d2e0e180b508243c764c661a7e
--3,4d3--
Sent from this host :  Max-Forwards: 5
Sent from this host :  To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
--5a5--
Received by server  :  To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
--8a9--
Received by server  :  max-forwards: 4
--11c12--
Sent from this host :  Content-Length: 252
Received by server  :  Content-Length:   254
--14c15--
Sent from this host :  o=vpujzk2x 21066632 3068032 IN IP4 192.168.1.102
Received by server  :  o=vpujzk2x 21066632 3068032 IN IP4 66.111.222.111
--16c17--
Sent from this host :  c=IN IP4 192.168.1.102
Received by server  :  c=IN IP4 66.111.222.111
--18c19--
Sent from this host :  m=audio 4731 RTP/AVP 8 0 3 101
Received by server  :  m=audio 7070 RTP/AVP 8 0 3 101
----------------------------------------------------------

__________________________________________________________________
INFO: SIP UDP ALG test result: TRUE
INFO: It seems that your router is performing ALG for SIP UDP
__________________________________________________________________

INFO: Starting the SIP TCP ALG test...

DEBUG: Connecting to the server (TCP:99.98.130.199:5060) ...

DEBUG: Sending SipAlgDetectorClient::InviteRequest to the server ...

DEBUG: Sent from 192.168.1.102:38055 to 99.98.130.199:5060:
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
INVITE sip:sip-alg-detector-daemon@99.98.130.199:5060 SIP/2.0
Via: SIP/2.0/TCP 192.168.1.102:6060;rport;branch=z9hG4bK82fsnsug
Max-Forwards: 5
To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
From: "SIP ALG Detector" <sip:sip-alg-detector@killing-alg-routers.war>;tag=wkv7m2m0
Call-ID: ch15ewuc25@192.168.1.102
CSeq: 422 INVITE
Contact: <sip:0123@192.168.1.102:6060;transport=tcp>
Allow: INVITE
Content-Type: application/sdp
Content-Length: 252

v=8
o=072xt6q2 66321564 3128200 IN IP4 192.168.1.102
s=-
c=IN IP4 192.168.1.102
t=0 0
m=audio 8628 RTP/AVP 8 0 3 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:3 GSM/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20
----------------------------------------------------------

DEBUG: Waiting for the responses from the server ...

DEBUG: 1/2 responses received

DEBUG: 2/2 responses received

DEBUG: Mirrored request sent in the response from the server:
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
INVITE sip:sip-alg-detector-daemon@99.98.130.199:5060 SIP/2.0
Via: SIP/2.0/TCP 192.168.1.102:6060;rport;branch=z9hG4bK82fsnsug
Max-Forwards: 5
To: <sip:sip-alg-detector-daemon@99.98.130.199:5060>
From: "SIP ALG Detector" <sip:sip-alg-detector@killing-alg-routers.war>;tag=wkv7m2m0
Call-ID: ch15ewuc25@192.168.1.102
CSeq: 422 INVITE
Contact: <sip:0123@192.168.1.102:6060;transport=tcp>
Allow: INVITE
Content-Type: application/sdp
Content-Length: 252

v=8
o=072xt6q2 66321564 3128200 IN IP4 192.168.1.102
s=-
c=IN IP4 192.168.1.102
t=0 0
m=audio 8628 RTP/AVP 8 0 3 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:3 GSM/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20
----------------------------------------------------------

INFO: No differences between sent request and received mirrored request

__________________________________________________________________
INFO: SIP TCP ALG test result: FALSE
INFO: It seems that your router is not performing ALG for SIP TCP
__________________________________________________________________


##################################################################
#     Test Results:
##    - SIP UDP ALG: TRUE
###   - SIP TCP ALG: FALSE
##################################################################


Return code: 21
```

* We could do the same in non-interactive mode:

```bash
~# ruby sip-alg-detector.rb -n -si 99.98.130.199
```

As we can see from the previous example, our router is performig SIP ALG for UDP (not for TCP). It behaves as a proxy (inserts a new "Via" header, decreases "Max-Forwards") and also replaces the private IP with the router public IP ("Contact" header and SDP).


## Author

* Iñaki Baz Castillo [[website](https://inakibaz.me)|[github](https://github.com/ibc/)]


## License

[GPL 2](./LICENSE)
