# included in runtests.jl
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


addsubproto("xml")
@schedule HTTP.listen("127.0.0.1", NEWPORT, tcpref = TCPREF2) do s
    if WebSockets.is_upgrade(s.message)
        WebSockets.upgrade((_)->nothing, s) 
    end
end
sleep(3)
# open client with approved subprotocol
const URL = "ws://127.0.0.1:$NEWPORT"
res = WebSockets.open((_)->nothing, URL, subprotocol = "xml");
@test res.status == 101
# open with unknown subprotocol
res = WebSockets.open((_)->nothing, URL, subprotocol = "unapproved");
@test res.status == 400
# try open with uknown port
caughterr = WebSockets.WebSocketClosedError("")
try 
WebSockets.open((_)->nothing, "ws://127.0.0.1:8099");
catch err
    caughterr = err
end
@test typeof(caughterr) <: WebSockets.WebSocketClosedError
@test caughterr.message == " while open ws|client: connect: connection refused (ECONNREFUSED)"

# start a client websocket that irritates by closing the TCP stream
# connection without a websocket closing handshake. This 
# throws an error in the server task
WebSockets.open("ws://127.0.0.1:$(NEWPORT)") do ws
    close(ws.socket)
end
# check that the server is still running regardless
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101
# Open with a ws client handler that throws a domain error
@test_throws DomainError WebSockets.open((_)->sqrt(-2), URL);
# Stop the TCP server
close(TCPREF2[])

# emulate a correct first accept response from server
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

# emulate an incorrect first accept response from server
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(base64encode(rand(UInt8, 16))))
write(servsock, resp)
@test_throws WebSockets.WebSocketError _openstream(dummywsh, s, key)
