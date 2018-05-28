using HTTP
using HttpServer
using WebSockets
using Base.Test
import WebSockets:  generate_websocket_key,
                    write_fragment,
                    read_frame,
                    websocket_handshake,
                    maskswitch!,
                    is_upgrade,
                    upgrade
import HttpServer:  is_websocket_handshake,
                    handle
import HttpCommon: Request
@sync yield() # avoid mixing of  output with possible deprecation warnings from .juliarc 
info("Starting test WebSockets...")
#is_control_frame is one line, checking one bit.
#get_websocket_key grabs a header.
#is_websocket_handshake grabs a header.
#generate_websocket_key makes a call to a library.
info("Test generate_websocket_key")
@test generate_websocket_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

"""
The dummy websocket don't use TCP. Close won't work, but we can manipulate the contents
using otherwise the same functions as TCP sockets.
"""
dummyws(server::Bool)  = WebSocket(BufferStream(), server)

function dummywshandler(req, dws::WebSockets.WebSocket{BufferStream})
    close(dws.socket)
    close(dws)
end


const io = IOBuffer()


info("Test length less than 126")
@testset "Unit test, fragment length less than 126" begin

for len = [8, 125], fin=[true, false], clientwriting = [false, true]

    op = (rand(UInt8) & 0b1111)
    test_str = randstring(len)
    # maskswitch two times with same key == unmasked
    maskunmask = copy(Vector{UInt8}(test_str))
    mskkey = maskswitch!(maskunmask)
    maskswitch!(maskunmask, mskkey)
    @test maskunmask == Vector{UInt8}(test_str)

    # websocket fragment as Vector{UInt8}
    # for client writing, the data is masked and the mask is contained in the frame.
    # for server writing, the data is not masked, and the header is four bytes shorter.
    write_fragment(io, fin, op, clientwriting, copy(Vector{UInt8}(test_str)))
    # test that the original input string was not masked.
    @test maskunmask == Vector{UInt8}(test_str)
    frame = take!(io)
    # Check the frame header 
    # Last frame bit
    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    # payload length bit
    @test frame[2] & 0b0111_1111 == len
    # ismasked bit
    hasmsk = frame[2] & 0b1000_0000 >>> 7 != 0
    @test hasmsk  == clientwriting
    # payload data
    if hasmsk
        framedata = copy(frame[7:end])
        maskswitch!(framedata, frame[3:6])
    else
        framedata = frame[3:end]
    end

    @test framedata == Vector{UInt8}(test_str)

    # Test for WebSocketError when reading
    #  masked frame-> websocket|server
    #  unmasked frame -> websocket|client

    # Let's pretend TCP has moved our frame into the peer websocket 
    receivingws = dummyws(!clientwriting)
    write(receivingws.socket, frame)
    @test_throws WebSockets.WebSocketError read_frame(receivingws)
    close(receivingws.socket)

    # Let's pretend receivingws didn't error like it should, but 
    # echoed our message back with identical masking. 
    dws = dummyws(clientwriting)
    @test dws.server == clientwriting
    write(dws.socket, frame)
    # read the frame back, now represented as a WebSocketFragment
   
    frag_back = read_frame(dws)
    close(dws.socket)
    @test frag_back.is_last == fin
    @test frag_back.rsv1 == false
    @test frag_back.rsv2 == false
    @test frag_back.rsv3 == false
    @test frag_back.opcode == op
    @test frag_back.is_masked == clientwriting
    @test frag_back.payload_len == len
    maskkey = UInt8[]
    if clientwriting
        maskkey = frame[3:6]
    end
    @test frag_back.maskkey == maskkey
    # the WebSocketFragment stores the data after unmasking
    @test Vector{UInt8}(test_str) == frag_back.data
end
end # testset


info("Test length 126 or more")
@testset "Unit test, fragment length 126 or more" begin

for len = 126:129, fin=[true, false], clientwriting = [false, true]
    op = 0b1111
    test_str = randstring(len)
    write_fragment(io, fin, op, clientwriting, copy(Vector{UInt8}(test_str)))
    frame = take!(io)

    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    @test frame[2] & 0b0111_1111 == 126
    @test bits(frame[4])*bits(frame[3]) == bits(hton(UInt16(len)))

    dws = dummyws(clientwriting)
    write(dws.socket, frame)
    frag_back = read_frame(dws)
    close(dws.socket)

    @test frag_back.is_last == fin
    @test frag_back.rsv1 == false
    @test frag_back.rsv2 == false
    @test frag_back.rsv3 == false
    @test frag_back.opcode == op
    @test frag_back.is_masked == clientwriting
    @test frag_back.payload_len == len
    @test test_str == String(frag_back.data)
end

end # testset
info("Test length typemax(UInt16) + 1")
@testset "Test length typemax(UInt16) + 1" begin

for clientwriting = [false, true]
    len = typemax(UInt16) +1
    op = 0b1111
    fin = true

    test_str = randstring(len)
    write_fragment(io, fin, op, clientwriting, copy(Vector{UInt8}(test_str)))
    frame = take!(io)

    dws = dummyws(clientwriting)
    write(dws.socket, frame)
    frag_back = read_frame(dws)
    close(dws.socket)

    @test frag_back.is_last == fin
    @test frag_back.rsv1 == false
    @test frag_back.rsv2 == false
    @test frag_back.rsv3 == false
    @test frag_back.opcode == op
    @test frag_back.is_masked == clientwriting
    @test frag_back.payload_len == len
    @test test_str == String(frag_back.data)
end

end # testset


@testset "Unit test, HttpServer and HTTP handshake" begin

info("Tests for is_websocket_handshake")
function templaterequests()
    chromeheaders = Dict{String, String}( "Connection"=>"Upgrade",
                                            "Upgrade"=>"websocket")
    firefoxheaders = Dict{String, String}("Connection"=>"keep-alive, Upgrade",
                                            "Upgrade"=>"websocket")

    chromerequest = HttpCommon.Request("GET", "", chromeheaders, "")
    firefoxrequest= Request("GET", "", firefoxheaders, "")

    chromerequest_HTTP = HTTP.Messages.Request("GET", "/", collect(chromeheaders))
    firefoxrequest_HTTP = HTTP.Messages.Request("GET", "/", collect(firefoxheaders))
    
    return [chromerequest, firefoxrequest, chromerequest_HTTP, firefoxrequest_HTTP]
end

chromerequest, firefoxrequest, chromerequest_HTTP, firefoxrequest_HTTP = Tuple(templaterequests())

wshandler = WebSocketHandler((x,y)->nothing)

for request in [chromerequest, firefoxrequest]
    @test is_websocket_handshake(wshandler, request) == true
end

for request in [chromerequest_HTTP, firefoxrequest_HTTP]
    @test is_upgrade(request) == true
end

info("Test of handshake response")
takefirstline(buf::IOBuffer) = strip(split(buf |> take! |> String, "\r\n")[1])
takefirstline(buf::BufferStream) = strip(split(buf |> read |> String, "\r\n")[1])
take!(io)

info("Test reject / switch format")
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


function handshakeresponse(request::Request)
    cli = HttpServer.Client(2, IOBuffer())
    websocket_handshake(request, cli)
    strip(takefirstline(cli.sock)) 
end
function handshakeresponse(request::HTTP.Messages.Request)
    buf = BufferStream()
    c = HTTP.ConnectionPool.Connection(buf)
    t = HTTP.Transaction(c)
    s = HTTP.Streams.Stream(request, t)
    upgrade(dummywshandler, s)
    close(buf)
    takefirstline(buf)
end

info("Test simple handshakes that are unacceptable")

sethd(r::Request, pa::Pair) = push!(r.headers, pa)
sethd(r::HTTP.Messages.Request, pa::Pair) = HTTP.Messages.setheader(r, HTTP.Header(pa)) 

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
    sethd(r,  "Sec-WebSocket-Key"       => "16 bytes key this is surely")
    sethd(r,  "Sec-WebSocket-Protocol"  => "unsupported")
    @test handshakeresponse(r) == REJECT
end





info("Test simple handshakes, acceptable")
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r,  "Sec-WebSocket-Key"       => "16 bytes key this is surely")
    @test handshakeresponse(r) == SWITCH
end



info("Test unacceptable subprotocol handshake subprotocol")
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r, "Sec-WebSocket-Key"        => "16 bytes key this is surely")
    sethd(r, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(r) == REJECT
end

info("add simple subprotocol to acceptable list")
@test true == WebSockets.addsubproto("xml") 

info("add subprotocol with difficult name")
@test true == WebSockets.addsubproto("my.server/json-zmq")

info("Test handshake subprotocol now acceptable")
for r in templaterequests()
    sethd(r, "Sec-WebSocket-Version"    => "13")
    sethd(r,  "Sec-WebSocket-Key"        => "16 bytes key this is surely")
    sethd(r, "Sec-WebSocket-Protocol"       => "xml")
    @test handshakeresponse(r) == SWITCH
    sethd(r, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(r) == SWITCH
end
end # testset

close(io)

@testset "Peer-to-peer tests, HTTP client" begin

const port_HTTP = 8000
const port_HTTP_ServeWS = 8001
const port_HttpServer = 8081


function echows(ws)
    while true
        data, success = readguarded(ws)
        !success && break
        !writeguarded(ws, data) && break
    end
end

function echows(req, ws)
    @test origin(req) == ""
    @test target(req) == "/"
    @test subprotocol(req) == ""
    while true
        data, success = readguarded(ws)
        !success && break
        !writeguarded(ws, data) && break
    end
end

info("Start HTTP listen server on port $port_HTTP")
@async HTTP.listen("127.0.0.1", UInt16(port_HTTP)) do s
    if WebSockets.is_upgrade(s.message)
        WebSockets.upgrade(echows, s) 
    end
end


info("Start HttpServer on port $port_HttpServer")
server = Server(WebSocketHandler(echows))
@async run(server, port_HttpServer)


info("Start HTTP ServerWS on port $port_HTTP_ServeWS") 
server_WS = WebSockets.ServerWS(
    HTTP.HandlerFunction(req-> HTTP.Response(200)), 
    WebSockets.WebsocketHandler(echows))

@async WebSockets.serve(server_WS, "127.0.0.1", port_HTTP_ServeWS, false)


sleep(4)

servers = [
    ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"), 
    ("HttpServer",  "ws://127.0.0.1:$(port_HttpServer)"),
    ("HTTTP ServerWS",  "ws://127.0.0.1:$(port_HTTP_ServeWS)"),
    ("ws",          "ws://echo.websocket.org"),
    ("wss",         "wss://echo.websocket.org")]

lengths = [0, 3, 125, 126, 127, 2000]

for (s, url) in servers, len in lengths, closestatus in [false, true]
    len == 0 && contains(url, "echo.websocket.org") && continue
    info("Testing client -> server at $(url), message length $len")
    test_str = randstring(len)
    forcecopy_str = test_str |> collect |> copy |> join
    WebSockets.open(url) do ws
        print(" -Foo-")
        write(ws, "Foo")
        @test String(read(ws)) == "Foo"
        print(" -Ping-")
        send_ping(ws)
        print(" -String length $len-\n")
        write(ws, test_str)
        @test String(read(ws)) == forcecopy_str
        closestatus && close(ws, statusnumber = 1000)
        sleep(0.2)
    end
    sleep(0.2)
end

end # testset

# TODO missing tests before browsertests.

# WebSockets.jl
# provoke errors WebSocketClosedError
# error("Attempted to send too much data for one websocket fragment\n")
# direct closing of tcp socket, while reading.
# closing with given reason (only from browsertests)
# unknown opcode
# Attempt to read from closed
# Read multiple frames (use dummyws), may require change
# InterruptException
# Protocol error (not masked from client)
# writeguarded, error


# HTTP
# open with optionalprotocol (change to subprotocol)
# open with rejected Protocol
# open bad reply to key during handshake (writeframe, dummyws)
# improve error handling in HTTP.open (may require change)
# HTTP messages that are not upgrades
# ugrade with single argument function
# ServeWS with https
# stop ServeWS with InterruptException
# listen with http request

# HttpServer
# exit without closing websocket 
# is_websocket_handshake with normal request
