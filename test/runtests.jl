using HTTP
using HttpServer
using WebSockets
using Base.Test
import WebSockets:  generate_websocket_key,
                    write_fragment,
                    read_frame,
                    websocket_handshake,
                    maskswitch!
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


# TODO: test for length > typemax(Uint32)
@testset "Unit test, HttpServer handshake" begin

info("Tests for is_websocket_handshake")
chromeheaders = Dict{String, String}(
        "Connection"=>"Upgrade",
        "Upgrade"=>"websocket"
    )
chromerequest = HttpCommon.Request(
    "GET",
    "",
    chromeheaders,
    ""
    )

firefoxheaders = Dict{String, String}(
        "Connection"=>"keep-alive, Upgrade",
        "Upgrade"=>"websocket"
    )

firefoxrequest= Request(
    "GET",
    "",
    firefoxheaders,
    ""
    )

wshandler = WebSocketHandler((x,y)->nothing);#Dummy wshandler

for request in [chromerequest, firefoxrequest]
    @test is_websocket_handshake(wshandler,request) == true
end

info("Test of handshake response")
takefirstline(buf) = split(buf |> take! |> String, "\r\n")[1]

take!(io)
Base.write(io, "test")
@test takefirstline(io) == "test"

info("Test reject / switch format")
const SWITCH = "HTTP/1.1 101 Switching Protocols "
const REJECT = "HTTP/1.1 400 Bad Request "
Base.write(io, Response(400))
@test takefirstline(io) == REJECT
Base.write(io, Response(101))
@test takefirstline(io) == SWITCH

function handshakeresponse(request)
    cli = HttpServer.Client(2, IOBuffer())
    websocket_handshake(request, cli)
    takefirstline(cli.sock) 
end

info("Test simple handshakes that are unacceptable")
for request in [chromerequest, firefoxrequest]
    @test handshakeresponse(request) == REJECT
    push!(request.headers, "Sec-WebSocket-Version"    => "13")
    @test handshakeresponse(request) == REJECT
    push!(request.headers,   "Sec-WebSocket-Key"        => "mumbojumbobo")
    @test handshakeresponse(request) == REJECT
    push!(request.headers, "Sec-WebSocket-Version"    => "11")
    push!(request.headers,  "Sec-WebSocket-Key"        => "zkG1WqHM8BJdQMXytFqiUw==")
    @test handshakeresponse(request) == REJECT
end

info("Test simple handshakes, acceptable")
for request in [chromerequest, firefoxrequest]
    push!(request.headers, "Sec-WebSocket-Version"    => "13")
    push!(request.headers,  "Sec-WebSocket-Key"        => "zkG1WqHM8BJdQMXytFqiUw==")
    @test handshakeresponse(request) == SWITCH
end

info("Test unacceptable subprotocol handshake subprotocol")
for request in [chromerequest, firefoxrequest]
    push!(request.headers, "Sec-WebSocket-Version"    => "13")
    push!(request.headers,  "Sec-WebSocket-Key"        => "zkG1WqHM8BJdQMXytFqiUw==")
    push!(request.headers, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(request) == REJECT
end

info("add simple subprotocol to acceptable list")
@test true == WebSockets.addsubproto("xml") 

info("add subprotocol with difficult name")
@test true == WebSockets.addsubproto("my.server/json-zmq")

info("Test handshake subprotocol now acceptable")
for request in [chromerequest, firefoxrequest]
    push!(request.headers, "Sec-WebSocket-Version"    => "13")
    push!(request.headers,  "Sec-WebSocket-Key"        => "zkG1WqHM8BJdQMXytFqiUw==")
    push!(request.headers, "Sec-WebSocket-Protocol"       => "xml")
    @test handshakeresponse(request) == SWITCH
    push!(request.headers, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(request) == SWITCH
end
end # testset

close(io)

@testset "Peer-to-peer tests, HTTP client" begin

const port_HTTP = 8000
const port_HttpServer = 8081

info("Start HTTP server on port $(port_HTTP)")

function echows(ws)
    while true
        data, success = readguarded(ws)
        !success && break
        !writeguarded(ws, data) && break
    end
end

@async HTTP.listen("127.0.0.1", UInt16(port_HTTP)) do http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(echows, http) 
    end
end

info("Start HttpServer on port $(port_HttpServer)")
wsh = WebSocketHandler() do req, ws
    echows(ws) 
end
server = Server(wsh)
@async run(server,port_HttpServer)

sleep(4)

servers = [
    ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"), 
    ("HttpServer",  "ws://127.0.0.1:$(port_HttpServer)"),
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
        sleep(1)
    end
    sleep(1)
end

end # testset


