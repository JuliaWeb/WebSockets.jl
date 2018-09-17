using Test
using HTTP
using WebSockets
import WebSockets:  is_upgrade,
                    upgrade,
                    _openstream,
                    addsubproto,
                    generate_websocket_key,
                    OPCODE_BINARY,
                    locked_write

import HTTP.Header
using Sockets
using Base64
import Base: BufferStream, convert
import Random.randstring

convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::HTTP.Messages.Response, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::HTTP.Messages.Response, pa::Header) = HTTP.Messages.setheader(r, pa)

#tests for #114
@info "Server send message first"

req = HTTP.Messages.Request()
req.method = "GET"
key = base64encode(rand(UInt8, 16))
resp = HTTP.Response(101)
resp.request = req
sethd(resp,   "Sec-WebSocket-Version" => "13")
sethd(resp, "Upgrade" => "websocket")
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(key))
sethd(resp,   "Connection" => "Upgrade")

for excesslen in 0:11, msglen in [0, 1, 2, 126, 65536]
    @info "test server first msg. -- max excess length($excesslen) message length($msglen)"
    fakesocket = BufferStream()
    s = HTTP.Streams.Stream(HTTP.Response(), HTTP.Transaction(HTTP.Connection(fakesocket)))
    write(fakesocket, resp)
    buffer = IOBuffer()
    mark(buffer)
    msg = randstring(msglen) |> Vector{UInt8}
    locked_write(buffer, true, OPCODE_BINARY, false, msg)
    reset(buffer)
    write(fakesocket, read(buffer, min(excesslen, msglen)))

    @test _openstream(s, key) do ws
        @sync begin
            @async @test msg == read(ws)
            write(fakesocket, readavailable(buffer))
        end
        close(fakesocket)
        return true
    end
end;

