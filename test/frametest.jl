# included in runtests.jl
using Test
import Sockets: TCPSocket
import Random: randstring
using WebSockets
import WebSockets: maskswitch!,
    write_fragment,
    read_frame,
    is_control_frame,
    handle_control_frame,
    locked_write,
    codeDesc
include("logformat.jl")

"""
The dummy websocket don't use TCP. Close won't work, but we can manipulate the contents
using otherwise the same functions as TCP sockets.
"""
dummyws(server::Bool)  = WebSocket(Base.BufferStream(), server)
io = IOBuffer()


# maskswitch
empty1 = UInt8[]
empty2 = UInt8[]
@test length(maskswitch!(empty1)) == 4
@test empty1 == empty2
# Test most basic frame, length <126

for len = [8, 125], fin=[true, false], clientwriting = [false, true]

    op = (rand(UInt8) & 0b1111)
    test_str = randstring(len)
    # maskswitch two times with same key == unmasked
    maskunmask = copy(codeunits(test_str))
    mskkey = maskswitch!(maskunmask)
    maskswitch!(maskunmask, mskkey)
    @test maskunmask == codeunits(test_str)

    # websocket fragment as Base.CodeUnits{UInt8,String}
    # for client writing, the data is masked and the mask is contained in the frame.
    # for server writing, the data is not masked, and the header is four bytes shorter.
    write_fragment(io, fin, op, clientwriting, copy(codeunits(test_str)))
    # test that the original input string was not masked.
    @test maskunmask == codeunits(test_str)
    frame = take!(io)
    # Check the frame header
    # Last frame bit
    @test bitstring(frame[1]) == (fin ? "1" : "0") * "000" * bitstring(op)[end-3:end]
    # payload length bit
    @test frame[2] & 0b0111_1111 == len
    # ismasked bit
    hasmsk = (frame[2] & 0b1000_0000) >>> 7 != 0
    @test hasmsk  == clientwriting
    # payload data
    if hasmsk
        framedata = copy(frame[7:end])
        maskswitch!(framedata, frame[3:6])
    else
        framedata = frame[3:end]
    end

    @test framedata == codeunits(test_str)

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
    @test codeunits(test_str) == frag_back.data
end

# Test length 126 or more

for len = 126:129, fin=[true, false], clientwriting = [false, true]
    op = 0b1111
    test_str = randstring(len)
    write_fragment(io, fin, op, clientwriting, copy(codeunits(test_str)))
    frame = take!(io)

    @test bitstring(frame[1]) == (fin ? "1" : "0") * "000" * bitstring(op)[end-3:end]
    @test frame[2] & 0b0111_1111 == 126
    @test bitstring(frame[4])*bitstring(frame[3]) == bitstring(hton(UInt16(len)))

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

# Test length typemax(UInt16) + 1

for clientwriting = [false, true]
    len = typemax(UInt16) +1
    op = 0b1111
    fin = true

    test_str = randstring(len)
    write_fragment(io, fin, op, clientwriting, copy(codeunits(test_str)))
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

# Test unknown opcodes

for op in 0xB:0xF
    clientwriting = false
    len = 10
    fin = true

    test_str = randstring(len)
    write_fragment(io, fin, op, clientwriting, copy(codeunits(test_str)))
    frame = take!(io)

    dws = dummyws(clientwriting)
    write(dws.socket, frame)
    frag_back = read_frame(dws)

    @test is_control_frame(frag_back)
    thiserror = ArgumentError("")
    try
        handle_control_frame(dws, frag_back)
    catch err
        thiserror = err
    end
    @test typeof(thiserror) <: ErrorException
    @test thiserror.msg == " while handle_control_frame(ws|client, wsf): Unknown opcode $op"

    close(dws.socket)
end


# Test multi-frame message

for clientwriting = [false, true]

    op = WebSockets.OPCODE_TEXT
    full_str = "123456"
    first_str = "123"
    second_str = "456"
    fin = false
    dws = dummyws(clientwriting)
    write_fragment(dws.socket, fin, op, clientwriting, copy(codeunits(first_str)))
    fin = true
    write_fragment(dws.socket, fin, op, clientwriting, copy(codeunits(second_str)))

    @test read(dws) == codeunits(full_str)
end




# Test read(ws) bad mask error handling

@info "Provoking close handshake from protocol error without a peer. Waits 10s, 'a reasonable time'."
for clientwriting in [false, true]
    op = WebSockets.OPCODE_TEXT
    test_str = "123456"
    fin = true
    write_fragment(io, fin, op, clientwriting, copy(codeunits(test_str)))
    frame = take!(io)
    # let's put this frame on the same kind of socket, and then read it as if it came from the peer
    # This will provoke a close handshake, but since there is no peer it times out.
    dws = dummyws(!clientwriting)
    write(dws.socket, frame)
    thiserror = ArgumentError("")
    try
        read(dws)
    catch err
        thiserror = err
    end
    @test typeof(thiserror) <: WebSocketClosedError
    expmsg = " while read(ws|$(dws.server ? "server" : "client")) WebSocket|$(dws.server ? "server" : "client") cannot handle incoming messages with$(dws.server ? "out" : "") mask. Ref. rcf6455 5.3 - Performed closing handshake."
    @test thiserror.message ==  expmsg
    @test !isopen(dws)
    close(dws.socket)

    # simple close frame
    clientwriting = false
end



# Close frame with no reason.
for clientwriting = [false, true]
    fin = true
    op = WebSockets.OPCODE_CLOSE
    write_fragment(io, fin, op, clientwriting, UInt8[])
    frame = take!(io)
    len = 0
    # Check the frame header
    # Last frame bit
    @test bitstring(frame[1]) == (fin ? "1" : "0") * "000" * bitstring(op)[end-3:end]
    # payload length bit
    @test frame[2] & 0b0111_1111 == len
    # ismasked bit
    hasmsk = (frame[2] & 0b1000_0000) >>> 7 != 0
    @test hasmsk  == clientwriting
    # the peer of the writer is
    dws = dummyws(clientwriting)
    write(dws.socket, frame)
    frag_back = read_frame(dws)
    @test frag_back.is_last == fin
    @test frag_back.opcode == op
    @test frag_back.is_masked == clientwriting
    @test frag_back.payload_len == len
    @test is_control_frame(frag_back)
end


# Close with no reason
for clientwriting in [false, true]
    op = WebSockets.OPCODE_CLOSE
    fin = true
    thisws = dummyws(!clientwriting)
    locked_write(thisws.socket, true, op, !thisws.server, UInt8[])
    close(thisws.socket)
    frame = read(thisws.socket)
    peerws = dummyws(clientwriting)
    write(peerws.socket, frame)
    close(peerws.socket)
    wsf = read_frame(peerws)
    @test is_control_frame(wsf)
    @test wsf.opcode == WebSockets.OPCODE_CLOSE
    @test wsf.payload_len == 0
end

# Close with status number
for clientwriting in [false, true], statusnumber in keys(codeDesc)
    op = WebSockets.OPCODE_CLOSE
    freereason = ""
    fin = true
    thisws = dummyws(!clientwriting)
    statuscode = reinterpret(UInt8, [hton(UInt16(statusnumber))])
    locked_write(thisws.socket, true, op, !thisws.server, statuscode)
    close(thisws.socket)
    frame = read(thisws.socket)

    # Check the frame header
    # Last frame bit
    @test bitstring(frame[1]) == (fin ? "1" : "0") * "000" * bitstring(op)[end-3:end]
    # payload length bit
    @test frame[2] & 0b0111_1111 == 2
    # ismasked bit
    hasmsk = (frame[2] & 0b1000_0000) >>> 7 != 0
    @test hasmsk  == clientwriting
    # the peer of the writer is
    peerws = dummyws(clientwriting)
    write(peerws.socket, frame)
    close(peerws.socket)
    wsf = read_frame(peerws)
    @test is_control_frame(wsf)
    @test wsf.opcode == WebSockets.OPCODE_CLOSE
    @test wsf.payload_len == 2
    scode = Int(reinterpret(UInt16, reverse(wsf.data))[1])
     @test scode == statusnumber
    reason = string(scode) * ":" * get(codeDesc, scode, "")
end

# Close with status number and freereason
for clientwriting in [false, true], statusnumber in keys(codeDesc)
    freereason = "q.e.d"
    op = WebSockets.OPCODE_CLOSE
    fin = true
    thisws = dummyws(!clientwriting)
    statuscode = vcat(reinterpret(UInt8, [hton(UInt16(statusnumber))]),
                codeunits(freereason))
    locked_write(thisws.socket, true, op, !thisws.server, copy(statuscode))
    close(thisws.socket)
    frame = read(thisws.socket)

    # Check the frame header
    # Last frame bit
    @test bitstring(frame[1]) == (fin ? "1" : "0") * "000" * bitstring(op)[end-3:end]
    # payload length bit
    @test frame[2] & 0b0111_1111 == length(statuscode)
    # ismasked bit
    hasmsk = (frame[2] & 0b1000_0000) >>> 7 != 0
    @test hasmsk  == clientwriting
    # the peer of the writer is
    peerws = dummyws(clientwriting)
    write(peerws.socket, frame)
    close(peerws.socket)
    wsf = read_frame(peerws)
    @test is_control_frame(wsf)
    @test wsf.opcode == WebSockets.OPCODE_CLOSE
    @test wsf.payload_len == length(statuscode)
    scode = Int(reinterpret(UInt16, reverse(wsf.data[1:2]))[1])
    reason = string(scode) * ":" *
            get(codeDesc, scode, "") *
            " " * String(wsf.data[3:end])
    @test reason == string(statusnumber) * ":" *
            get(codeDesc, statusnumber, "") *
            " " * freereason
end


close(io)
