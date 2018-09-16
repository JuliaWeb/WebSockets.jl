using Test
using HTTP
using WebSockets
import WebSockets:  is_upgrade,
                    upgrade,
                    _openstream,
                    addsubproto,
                    generate_websocket_key,
                    OPCODE_BINARY,
                    write_fragment

import HTTP.Header
using Sockets
using Base64
import Base: BufferStream, convert
convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::HTTP.Messages.Response, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::HTTP.Messages.Response, pa::Header) = HTTP.Messages.setheader(r, pa)

@info "tests for #114"

req = HTTP.Messages.Request()
req.method = "GET"
key = base64encode(rand(UInt8, 16))
resp = HTTP.Response(101)
resp.request = req
sethd(resp,   "Sec-WebSocket-Version" => "13")
sethd(resp, "Upgrade" => "websocket")
sethd(resp, "Sec-WebSocket-Accept" => generate_websocket_key(key))
sethd(resp,   "Connection" => "Upgrade")
fakesocket = BufferStream()
s = HTTP.Streams.Stream(resp, HTTP.Transaction(HTTP.Connection(fakesocket)))
write(fakesocket, resp)
firstmsg = Vector{UInt8}("HI.")
write_fragment(fakesocket, true, OPCODE_BINARY, false, firstmsg)
@debug "data ready" fakesocket
received = b""
@testset "tests for #114" begin
@test _openstream(s, key) do ws
  @debug "reading" ws.socket ws.state
  @test s.stream === ws.socket
  received = read(ws)
  close(fakesocket)
  @debug "after read"
  return received
end == firstmsg
end