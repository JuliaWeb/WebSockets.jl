# included in runtests.jl
# focus on HTTP.jl
using Base.Test
using HTTP
import WebSockets:  is_upgrade,
                    upgrade,
                    _openstream,
                    addsubproto,
                    generate_websocket_key

sethd(r::HTTP.Messages.Response, pa::Pair) = HTTP.Messages.setheader(r, HTTP.Header(pa))

const NEWPORT = 8091
const TCPREF2 = Ref{Base.TCPServer}()

@info("start HTTP server\n")
sleep(1)
addsubproto("xml")
tas = @async HTTP.listen("127.0.0.1", NEWPORT, tcpref = TCPREF2) do s
    if WebSockets.is_upgrade(s.message)
        WebSockets.upgrade((_)->nothing, s)
    end
end
while !istaskstarted(tas);yield();end

@info("open client with approved subprotocol\n")
sleep(1)
URL = "ws://127.0.0.1:$NEWPORT"
res = WebSockets.open((_)->nothing, URL, subprotocol = "xml");
@test res.status == 101

@info("open with unknown subprotocol\n")
sleep(1)
res = WebSockets.open((_)->nothing, URL, subprotocol = "unapproved");
@test res.status == 400

@info("try open with uknown port\n")
sleep(1)
caughterr = WebSockets.WebSocketClosedError("")
try
WebSockets.open((_)->nothing, "ws://127.0.0.1:8099");
catch err
    caughterr = err
end
@test typeof(caughterr) <: WebSockets.WebSocketClosedError
@test caughterr.message == " while open ws|client: connect: connection refused (ECONNREFUSED)"

@info("try open with uknown scheme\n")
sleep(1)
caughterr = ArgumentError("")
try
WebSockets.open((_)->nothing, "ww://127.0.0.1:8099");
catch err
    caughterr = err
end
@test typeof(caughterr) <: ArgumentError
@test caughterr.msg == " bad argument url: Scheme not ws or wss. Input scheme: ww"


caughterr = ArgumentError("")
try
WebSockets.open((_)->nothing, "ws://127.0.0.1:8099/svg/#");
catch err
    caughterr = err
end
@test typeof(caughterr) <: ArgumentError
@test caughterr.msg == " replace '#' with %23 in url: ws://127.0.0.1:8099/svg/#"

@info("start a client websocket that irritates by closing the TCP stream
 connection without a websocket closing handshake. This
 throws an error in the server task\n")
sleep(1)
WebSockets.open("ws://127.0.0.1:$(NEWPORT)") do ws
    close(ws.socket)
end

@info("check that the server is still running regardless\n")
sleep(1)
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101

@info("Open with a ws client handler that throws a domain error\n")
sleep(1)
@test_throws DomainError WebSockets.open((_)->sqrt(-2), URL);

@info("Stop the TCP server\n")
sleep(1)
close(TCPREF2[])
sleep(1)
@info("Emulate a correct first accept response from server, with BufferStream socket\n")
sleep(1)
req = HTTP.Messages.Request()
req.method = "GET"
key = base64encode(rand(UInt8, 16))
resp = HTTP.Response(101)
resp.request = req
sethd(resp,   "Sec-WebSocket-Version" => "13")
sethd(resp, "Upgrade" => "websocket")
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(key))
sethd(resp,   "Connection" => "Upgrade")
servsock = BufferStream()
s = HTTP.Streams.Stream(resp, HTTP.Transaction(HTTP.Connection(servsock)))
write(servsock, resp)
function dummywsh(dws::WebSockets.WebSocket{BufferStream})
    close(dws.socket)
    close(dws)
end
@test _openstream(dummywsh, s, key) == WebSockets.CLOSED

@info("emulate an incorrect first accept response from server\n")
sleep(1)
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(base64encode(rand(UInt8, 16))))
write(servsock, resp)
@test_throws WebSockets.WebSocketError _openstream(dummywsh, s, key)
