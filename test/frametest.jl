# included in runtests.jl
using Base.Test
import WebSockets: maskswitch!,
    write_fragment,
    read_frame,
    WebSocket

"""
The dummy websocket don't use TCP. Close won't work, but we can manipulate the contents
using otherwise the same functions as TCP sockets.
"""
dummyws(server::Bool)  = WebSocket(BufferStream(), server)
    

io = IOBuffer()
# Test most basic frame, length <126

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

# Test length 126 or more

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

# Test length typemax(UInt16) + 1

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
