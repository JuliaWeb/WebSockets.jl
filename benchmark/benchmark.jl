#=
TERMINOLOGY

Client          The side of a connection which initiates.
Server          The side of a connection which accepts.
Origin          Sender
Destination     Receiver
HTS             HTTP server
JCE             Julia Client Echoing
BCE             Browser Client Echoing

Note we use 'inverse speed' below. In lack of better words, we call this speed.
This is more compatible with BenchmarkTools and more directly useful.
For some fun reasoning, refer https://www.lesswrong.com/posts/qNiH3RRTiXXyvMJRg/inverse-speed

Note 'latency' can also be defined in other ways. Ad hoc:

speed           [ns/b]  time / amount
messagesize     [b]     Datasize for an individual message (one or more frames)
clientlatency   [ns]    Time from start sending from client to having received on destination
serverlatency   [ns]    Time from start sending from server to having received on destination
clientspeed     [ns/b] = [s/GB]
                        = upspeed = clientlatency / messagesize
                        For JCE: Client sends the message, server records its having received time
                        For BCE: Server sends the message, client sends back two messages of different lengths.
                                 Clientspeed is calculated from server time records.
serverspeed     [ns/b] = [s/GB]
                        = Downspeed = serverlatency / messagesize
                        For JCE: Server sends the message, client measures its having received time
                        For BCE: Server sends the message, client sends back two messages of different lengths.
                                 Serverspeed is calculated from server time records.
clientbandwidth [ns/b] = [s/GB]
                          Average clientspeed, time per datasize
serverbandwidth [ns/b] = [s/GB]
                         Average serverspeed, time per datasize

=#

#=
-----  TODO  ----

Not used:
** delay           [ns]    Time usefully spent between received message and start of reply
** clientRTT       [ns]    Round-trip-time for a message initiated by client
** serverRTT       [ns]    Round-trip-time for a message initiated by server
** Up2down      ClientBandwidth / ServerBandwidth
** throughput   datasize / (RTT - Delay)
** serversize      [b]     Messagesize from server
** clientsize      [b]     Messagesize from client



Outlined benchmarks for optimizing WebSockets:

- Clientlatency() @ Bandwidth ≈ 0, Clientmessage = 1b
    Requires some tweaking of BenchMarkTools.Trial, postponed.
- Serverlatency() @ Bandwidth ≈ 0, Servermessage = 1b
    Requires some tweaking of BenchMarkTools.Trial, postponed.
- Maximized bandwidth(VSIZE) @ Up2Down ≈ 1
    Not using BenchmarkTools directly
- ClientRTT(VDELAY) @ Bandwidth ≈ 0, Clientmessage = 1b
- ServerRTT(VDELAY) @ Bandwidth ≈ 0, Servermessage = 1b
    The last two checks vs. possibly related issue #1608 on ZMQ



Outlined benchmarks for developing an application using WebSockets (postponed):
- ClientRTT(VSIZE) @ Bandwidth[0%, 50%, 100%]
    ClientRTT determines user responsiveness, e.g. mouse clicks in a browser
    This requires small messages or threaded read / write (async has to wait for
    the server finishing sending its message)
- Bandwidth(VUP2DOWN, VSIZE)
    This depends on the network in use and operating system
        [(up2down, msize)  for up2down in VUP2DOWN for msize in VSIZE]
- Serverlatency(VSIZE) @ Bandwidth[0%, 50%, 100%]
    The outliers (due to e.g. semi-random garbage collection) determines
    choice of message size and buffers for media streams
- Clientlatency() @ 100% bandwidth @ Up2Down
    The outliers (due to e.g. semi-random garbage collection) determines
    choice of message size and buffers for long-running calculations which
    connects to a server for distribution of results
=#
# Don't run this if the output files are recent?
include("benchmark_prepare.jl")
# TODO include detailed benchmarks using the results from the above as nominal.
