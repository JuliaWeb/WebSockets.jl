# included in runtests.jl
# Opening / closing / triggering errors without crashing server.
using Test
using WebSockets
import WebSockets:  is_upgrade,
                    upgrade,
                    _openstream,
                    generate_websocket_key,
                    Header,
                    Response,
                    Request,
                    Stream,
                    Transaction,
                    Connection,
                    setheader
using Base64
import Base: BufferStream, convert
include("logformat.jl")
convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::Response, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::Response, pa::Header) = setheader(r, pa)

const NEWPORT = 8091

@info "Start server which accepts websocket upgrades including with subprotocol " *
      "'xml' and immediately closes, following protocol."
addsubproto("xml")
serverWS =  ServerWS(  (r::Request) -> Response(200, "OK"),
                       (r::Request, ws::WebSocket) -> nothing)
tas = @async WebSockets.serve(serverWS, "127.0.0.1", NEWPORT)
while !istaskstarted(tas);yield();end

@info "Open client without subprotocol."
sleep(1)
URL = "ws://127.0.0.1:$NEWPORT"
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101


@info "Open client with approved subprotocol."
sleep(1)
URL = "ws://127.0.0.1:$NEWPORT"
res = WebSockets.open((_)->nothing, URL, subprotocol = "xml");
@test res.status == 101

@info "Open with unknown subprotocol."
sleep(1)
res = WebSockets.open((_) -> nothing, URL, subprotocol = "unapproved");
@test res.status == 400

@info "Try to open a websocket with uknown port. Takes a few seconds."
sleep(1)
global caughterr = WebSockets.WebSocketClosedError("")
try
WebSockets.open((_)->nothing, "ws://127.0.0.1:8099");
catch err
    global caughterr = err
end
@test typeof(caughterr) <: WebSocketClosedError
@test caughterr.message == " while open ws|client: connect: connection refused (ECONNREFUSED)"

@info "Try open with uknown scheme."
sleep(1)
global caughterr = ArgumentError("")
try
WebSockets.open((_)->nothing, "ww://127.0.0.1:8099");
catch err
    global caughterr = err
end
@test typeof(caughterr) <: ArgumentError
@test caughterr.msg == " bad argument url: Scheme not ws or wss. Input scheme: ww"


global caughterr = ArgumentError("")
try
WebSockets.open((_)->nothing, "ws://127.0.0.1:8099/svg/#");
catch err
    global caughterr = err
end
@test typeof(caughterr) <: ArgumentError
@test caughterr.msg == " replace '#' with %23 in url: ws://127.0.0.1:8099/svg/#"

@info "start a client websocket that irritates by closing the TCP stream
 connection without a websocket closing handshake. This
 throws an error in the server coroutine, which can't be
 captured on the server side."
sleep(1)
WebSockets.open("ws://127.0.0.1:$(NEWPORT)") do ws
    close(ws.socket)
end

@info "Check that the server is still running regardless."
sleep(1)
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101

@info "Open with a ws client handler that throws a domain error."
sleep(1)
@test_throws DomainError WebSockets.open((_)->sqrt(-2), URL);

@info "Stop the server in morse code."
sleep(1)
put!(serverWS.in, "...-.-")
sleep(1)
@info "Emulate a correct first accept response from server, with BufferStream socket."
sleep(1)
req = Request()
req.method = "GET"
key = base64encode(rand(UInt8, 16))
resp = Response(101)
resp.request = req
sethd(resp,   "Sec-WebSocket-Version" => "13")
sethd(resp, "Upgrade" => "websocket")
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(key))
sethd(resp,   "Connection" => "Upgrade")
servsock = BufferStream()
s = Stream(resp, Transaction(Connection(servsock)))
write(servsock, resp)
function dummywsh(dws::WebSockets.WebSocket{BufferStream})
    close(dws.socket)
    close(dws)
end
@test _openstream(dummywsh, s, key) == WebSockets.CLOSED

@info "Emulate an incorrect first accept response from server."
sleep(1)
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(base64encode(rand(UInt8, 16))))
write(servsock, resp)
@test_throws WebSockets.WebSocketError _openstream(dummywsh, s, key)
nothing
