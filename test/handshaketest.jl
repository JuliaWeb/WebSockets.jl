# included in runtests.jl
using Test
import WebSockets.HTTP
import Base: convert, BufferStream
using WebSockets
import WebSockets:  generate_websocket_key, upgrade

include("logformat.jl")
include("handshaketest_functions.jl")

# Test generate_websocket_key"
@test generate_websocket_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="


# Test reject / switch format"
io = IOBuffer()
const REJECT = "HTTP/1.1 400 Bad Request"
Base.write(io, HTTP.Response(400))
@test takefirstline(io) == REJECT
Base.write(io, HTTP.Response(400))
@test takefirstline(io) == REJECT

const SWITCH = "HTTP/1.1 101 Switching Protocols"
Base.write(io, HTTP.Response(101))
@test takefirstline(io) == SWITCH
Base.write(io, HTTP.Response(101))
@test takefirstline(io) == SWITCH

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
