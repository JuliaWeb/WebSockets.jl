using WebSockets
using Compat; import Compat.String
using Base.Test
import WebSockets: generate_websocket_key,
                   write_fragment,
                   read_frame,
                   is_websocket_handshake,
                   websocket_handshake,
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

# Test writing

function xor_payload(maskkey, data)
  out = Array{UInt8,1}(length(data))
  for i in 1:length(data)
    d = data[i]
    d = @compat xor(d , maskkey[mod(i - 1, 4) + 1])
    out[i] = d
  end
  out
end

const io = IOBuffer()

info("Test length less than 126")
for len = [8, 125], op = (rand(UInt8) & 0b1111), fin=[true, false]

    test_str = randstring(len)
    write_fragment(io, fin, Vector{UInt8}(test_str), op)

    frame = take!(io)

    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    @test frame[2] == UInt8(len)
    @test String(frame[3:end]) == test_str

    # Check to see if reading message without a mask fails
    in_buf = IOBuffer(String(frame))
    @test_throws ErrorException read_frame(in_buf)
    close(in_buf)

    # add a mask
    maskkey = rand(UInt8, 4)
    data = vcat(
        frame[1],
        frame[2] | 0b1000_0000,
        maskkey,
        xor_payload(maskkey, frame[3:end])
    )
    frame_back = read_frame(IOBuffer(data))

    @test frame_back.is_last == fin
    @test frame_back.rsv1 == false
    @test frame_back.rsv2 == false
    @test frame_back.rsv3 == false
    @test frame_back.opcode == op
    @test frame_back.is_masked == true
    @test frame_back.payload_len == len
    @test all(map(==, frame_back.maskkey, maskkey))
    @test test_str == String(frame_back.data)
end

info("Test length 126 or more")
for len = 126:129, op = 0b1111, fin=[true, false]

    test_str = randstring(len)
    write_fragment(io, fin, Vector{UInt8}(test_str), op)

    frame = take!(io)

    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    @test frame[2] == 126

    @test bits(frame[4])*bits(frame[3]) == bits(hton(UInt16(len)))

    # add a mask
    maskkey = rand(UInt8, 4)
    data = vcat(
        frame[1],
        frame[2] | 0b1000_0000,
        frame[3],
        frame[4],
        maskkey,
        xor_payload(maskkey, frame[5:end])
    )
    frame_back = read_frame(IOBuffer(data))

    @test frame_back.is_last == fin
    @test frame_back.rsv1 == false
    @test frame_back.rsv2 == false
    @test frame_back.rsv3 == false
    @test frame_back.opcode == op
    @test frame_back.is_masked == true
    @test frame_back.payload_len == len
    @test all(map(==, frame_back.maskkey, maskkey))
    @test test_str == String(frame_back.data)
end

# TODO: test for length > typemax(Uint32)

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
Base.write(io, WebSockets.Response(400))
@test takefirstline(io) == REJECT
Base.write(io, WebSockets.Response(101))
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
@test true == WebSockets.@addsubproto xml 

info("add subprotocol with difficult name")
@test true == WebSockets.@addsubproto "my.server/json-zmq"

info("Test handshake subprotocol now acceptable")
for request in [chromerequest, firefoxrequest]
    push!(request.headers, "Sec-WebSocket-Version"    => "13")
    push!(request.headers,  "Sec-WebSocket-Key"        => "zkG1WqHM8BJdQMXytFqiUw==")
    push!(request.headers, "Sec-WebSocket-Protocol"       => "xml")
    @test handshakeresponse(request) == SWITCH
    push!(request.headers, "Sec-WebSocket-Protocol"       => "my.server/json-zmq")
    @test handshakeresponse(request) == SWITCH
end
close(io)