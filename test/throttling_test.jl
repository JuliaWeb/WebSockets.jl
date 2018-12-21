# included in runtests.jl
# tests throttling and secure server options.
using Test
using WebSockets
import WebSockets: checkratelimit!,
                RateLimit,
                SSLConfig
using Sockets
using Dates
include("logformat.jl")

# Get an argument for testing checkratelimit! directly

@info "Unit tests for checkratelimit."

_, tcpserver = listenany(8767)

@test_throws ArgumentError checkratelimit!(tcpserver)

@test_throws ArgumentError checkratelimit!(tcpserver)
try
    checkratelimit!(tcpserver)
catch err
    @test err.msg == " checkratelimit! called without keyword argument " *
                    "ratelimits::Dict{IPAddr, RateLimit}(). "
end

# A dictionary keeping track, default rate limit
ratedic = Dict{IPAddr, RateLimit}()
@test checkratelimit!(tcpserver, ratelimits = ratedic)
@test ratedic[getsockname(tcpserver)[1]].allowance == 9

function countconnections(maxfreq, timeinterval)
    ratedic = Dict{IPAddr, RateLimit}()
    counter = 0
    t0 = now()
    while now() - t0 <= timeinterval
        if checkratelimit!(tcpserver, ratelimits = ratedic, ratelimit = maxfreq)
            counter +=1
        end
        yield()
    end
    counter
end
countconnections(1//1, Millisecond(500))
@test countconnections(1//1, Millisecond(500)) == 1
@test countconnections(1//1, Millisecond(1900)) == 2
@test countconnections(1//1, Millisecond(2900)) == 3
@test countconnections(10//1, Millisecond(10)) == 10
@test countconnections(10//1, Millisecond(200)) in [11, 12]
@test countconnections(10//1, Millisecond(1000)) in [19, 20]
close(tcpserver)

@info "Make http request to a server with specified ratelimit 1 new connections // 1 second"
if !@isdefined(THISPORT)
    const THISPORT = 8091
end
const IPA = "127.0.0.1"
const URL9 = "http://$IPA:$THISPORT"
serverWS =  ServerWS(  (r) -> WebSockets.Response(200, "OK"),
                       (r, ws) -> nothing,
                       ratelimit = 1 // 1)
tas = @async WebSockets.serve(serverWS, IPA, THISPORT)
while !istaskstarted(tas);yield();end


function countresponses(timeinterval)
    counter = 0
    t0 = now()
    while now() - t0 <= timeinterval
        if WebSockets.HTTP.request("GET", URL9, reuse_limit = 1).status == 200
            counter += 1
        end
    end
    counter
end
countresponses(Millisecond(500))
@test countresponses(Millisecond(3500)) in [3, 4]
put!(serverWS.in, "closeit")

@info "Set up a secure server, missing local certificates. Http request should throw error (15s). "
serverWS =  ServerWS(  (r) -> WebSockets.Response(200, "OK"),
                       (r, ws) -> nothing,
                       sslconfig = SSLConfig())

tas = @async WebSockets.serve(serverWS, host = IPA, port =THISPORT)
const URL10 = "https://$IPA:$THISPORT"
@test_throws WebSockets.HTTP.IOExtras.IOError WebSockets.HTTP.request("GET", URL10)
const WSSURI = "wss://$IPA:$THISPORT"
@info "Websocket upgrade request should throw error (15s)."
@test_throws WebSocketClosedError WebSockets.open((_)->nothing, WSSURI)
nothing
