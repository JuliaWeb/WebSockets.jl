# This is not included in runtestss.jl
# focus on HTTP.jl

# stdlibs, no declared dependecy
using Test
using Logging
using Test

import WebSockets
import WebSockets:  is_upgrade,
                    upgrade,
                    generate_websocket_key
import WebSockets.HTTP
import HTTP: Header,
             Messages.Response,
             Messages.setheader,
             Streams.Stream,
             Transaction,
             Connection,
             IPAddr,
             IPv4,
             Servers.check_rate_limit,
             Servers.RateLimit
using HTTP.Sockets
import Sockets:getsockname,
               listenany,
               IPv4
import Base: convert
using Dates


convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::Response, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::Response, pa::Header) = setheader(r, pa)


const PORT2 = 8091
const IP =  "127.0.0.1"
const URL = "ws://" * IP * ":" * string(PORT2)

maxfreq = 1//1
port, tcpserver = listenany(8767)
ip, po = getsockname(tcpserver)
ipa = IPv4( 127, 0,0,1)
# A mutable dictionary. For every IPAddr, maintains a RateLimit.
# The RateLimit is a structure with the ratelimit value,
# set by user, and the used allowance, updated every request.
lastreqdic = Dict{IPAddr, RateLimit}()
# if this server hasn't got a logged request from before,
# use this entry instead.
rli = RateLimit(maxfreq, now())
rl = get!(lastreqdic, ip, rli)
check_rate_limit(tcpserver,
    ratelimits = lastreqdic,
    ratelimit = maxfreq)
rl2 = get!(lastreqdic, ip, rli)

print(rl2.lastcheck)
check_rate_limit(tcpserver,
    ratelimits = lastreqdic,
    ratelimit = maxfreq)





print(lastreqdic



rl == rl2


deltaminwait = 1 / maxfreq
@show(port)
println("Listening on port ", Int(port))
println("The socket name is ", getsockname(tcpserver))
println("The socket type is ", typeof(getsockname(tcpserver)))

push!(lareqdic, IPAddr())
println("The rate limit dictionary is ", lastreqdic)
HTTP.Servers.check_rate_limit(tcpserver,
    ratelimits = lastreqdic,
    ratelimit = maxfreq)



function waitforacceptance(maxfreq::Rational{Int}=Int(10)//Int(1))

    t0 = now()
    while !HTTP.Servers.check_rate_limit(tcpsocket, ratelimit = maxfreq)
        sleep(0.001)
    end
    now() - t0
end

waitforacceptance(5//1)
function validator(tcp::Stream; )

end

@info "Start HTTP server with throttling limit $reqfreq request per second"
acceptthisrequest(tcp, kw...) = HTTP.Servers.check_rate_limit(tcp, kw...)








function serve2(reqfreq)
    serverref = Ref{Base.IOServer}()
    tas = @async HTTP.listen(IP, PORT2, tcpref = serverref, isvalid = acceptthisrequest) do s
        if is_upgrade(s.message)
            upgrade((_)->nothing, s)
        end
    end
    while !istaskstarted(tas);yield();end
    return serverref
end

global reqfreq = 1# requests per second before throttling.
deltaminwait = 1 / reqfreq



res = WebSockets.open((_)->nothing, URL, subprotocol = "xml");
@test res.status == 101
