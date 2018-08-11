# included in runtests.jl
using Test
using HTTP
using WebSockets
using BufferedStreams
import Base: convert, BufferStream
import HTTP.Header

import WebSockets:  generate_websocket_key, upgrade



function templaterequests()
    chromeheaders = Dict{String, String}( "Connection"=>"Upgrade",
                                            "Upgrade"=>"websocket")
    firefoxheaders = Dict{String, String}("Connection"=>"keep-alive, Upgrade",
                                            "Upgrade"=>"websocket")
    chromerequest_HTTP = HTTP.Messages.Request("GET", "/", collect(chromeheaders))
    firefoxrequest_HTTP = HTTP.Messages.Request("GET", "/", collect(firefoxheaders))
    return [chromerequest_HTTP, firefoxrequest_HTTP]
end
convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::HTTP.Messages.Request, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::HTTP.Messages.Request, pa::Header) = HTTP.Messages.setheader(r, pa)

takefirstline(buf::IOBuffer) = strip(split(buf |> take! |> String, "\r\n")[1])
takefirstline(buf::BufferStream) = strip(split(buf |> read |> String, "\r\n")[1])
function handshakeresponse(request::HTTP.Messages.Request)
    buf = BufferStream()
    c = HTTP.ConnectionPool.Connection(buf)
    t = HTTP.Transaction(c)
    s = HTTP.Streams.Stream(request, t)
    upgrade(dummywshandler, s)
    close(buf)
    takefirstline(buf)
end

"""
The dummy websocket don't use TCP. Close won't work, but we can manipulate the contents
using otherwise the same functions as TCP sockets.
"""
dummyws(server::Bool)  = WebSocket(BufferStream(), server)

function dummywshandler(req, dws::WebSockets.WebSocket{BufferStream})
    close(dws.socket)
    close(dws)
end

# Test generate_websocket_key"
@test generate_websocket_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="


# Test reject / switch format"
io = IOBuffer()
const REJECT = "HTTP/1.1 400 Bad Request"
Base.write(io, Response(400))
@test takefirstline(io) == REJECT
Base.write(io, HTTP.Messages.Response(400))
@test takefirstline(io) == REJECT

const SWITCH = "HTTP/1.1 101 Switching Protocols"
Base.write(io, Response(101))
@test takefirstline(io) == SWITCH
Base.write(io, HTTP.Messages.Response(101))
@test takefirstline(io) == SWITCH


chromerequest, firefoxrequest, chromerequest_HTTP, firefoxrequest_HTTP = Tuple(templaterequests())
wshandler = WebSocketHandler((x,y)->nothing)
for request in [chromerequest, firefoxrequest]
    @test is_websocket_handshake(wshandler, request) == true
end


# "Test simple handshakes that are unacceptable"

for r in templaterequests()
    @test handshakeresponse(r) == REJECT
    sethd(r, "Sec-WebSocket-Version"    => "11")
    @test handshakeresponse(r) == REJECT
    sethd(r, "Sec-WebSocket-Version"    => "13")
    @test handshakeresponse(r) == REJECT
    sethd(r,   "Sec-WebSocket-Key"      => "mumbojumbobo")
    @test handshakeresponse(r) == REJECT
    sethd(r,  "Sec-WebSocket-Key"       => "17 bytes key is not accepted")
    @test handshakeresponse(r) == REJECT
    sethd(r,  "Sec-WebSocket-Key"       => "AQIDBAUGBwgJCgsMDQ4PEA==")
    sethd(r,  "Sec-WebSocket-Protocol"  => "unsupported")
    @test handshakeresponse(r) == REJECT
end


#  Test simple handshakes, acceptable
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r,  "Sec-WebSocket-Key"       => "AQIDBAUGBwgJCgsMDQ4PEA==")
    @test handshakeresponse(r) == SWITCH
end



#  Test unacceptable subprotocol handshake subprotocol
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r, "Sec-WebSocket-Key"        => "AQIDBAUGBwgJCgsMDQ4PEA==")
    sethd(r, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(r) == REJECT
end

#  add simple subprotocol to acceptable list
@test true == WebSockets.addsubproto("xml")

# add subprotocol with difficult name
@test true == WebSockets.addsubproto("my.server/json-zmq")

# "Test handshake subprotocol now acceptable"
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r,  "Sec-WebSocket-Key"        => "AQIDBAUGBwgJCgsMDQ4PEA==")
    sethd(r, "Sec-WebSocket-Protocol"       => "xml")
    @test handshakeresponse(r) == SWITCH
    sethd(r, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(r) == SWITCH
end
