using WebSockets
using Compat; import Compat.String
using Base.Test

import WebSockets: generate_websocket_key,
                   write_fragment,
                   read_frame,
                   is_websocket_handshake

import HttpCommon: Request

#is_control_frame is one line, checking one bit.
#get_websocket_key grabs a header.
#is_websocket_handshake grabs a header.

#generate_websocket_key makes a call to a library.
@test generate_websocket_key("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

# Test writing

function xor_payload(maskkey, data)
    out = Array(UInt8, length(data))
  for i in 1:length(data)
    d = data[i]
    d = d $ maskkey[mod(i - 1, 4) + 1]
    out[i] = d
  end
  out
end

const io = IOBuffer()

# Length less than 126
for len = [8, 125], op = (rand(UInt8) & 0b1111), fin=[true, false]

    test_str = randstring(len)
    write_fragment(io, fin, test_str, op)

    frame = takebuf_array(io)

    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    @test frame[2] == @compat UInt8(len)
    @test String(frame[3:end]) == test_str

    # Check to see if reading message without a mask fails
    in_buf = IOBuffer(frame)
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

# Length 126 or more
for len = 126:129, op = 0b1111, fin=[true, false]

    test_str = randstring(len)
    write_fragment(io, fin, test_str, op)

    frame = takebuf_array(io)

    @test bits(frame[1]) == (fin ? "1" : "0") * "000" * bits(op)[end-3:end]
    @test frame[2] == 126

    @test bits(frame[4])*bits(frame[3]) == bits(hton(@compat UInt16(len)))

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

#
close(io)

# Tests for is_websocket_handshake
chromeheaders = @compat Dict{AbstractString,AbstractString}(
        "Connection"=>"Upgrade",
        "Upgrade"=>"websocket"
    )
chromerequest = Request(
    "GET",
    "",
    chromeheaders,
    ""
    )

firefoxheaders = @compat Dict{AbstractString,AbstractString}(
        "Connection"=>"keep-alive, Upgrade",
        "Upgrade"=>"websocket"
    )

firefoxrequest= Request(
    "GET",
    "",
    firefoxheaders,
    ""
    )

handler = WebSocketHandler(x->x); #Dummy handler

for request in [chromerequest, firefoxrequest]
    @test is_websocket_handshake(handler,request) == true
end
