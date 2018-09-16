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
fakesocket = PipeBuffer()
s = HTTP.Streams.Stream(resp, HTTP.Transaction(HTTP.Connection(fakesocket)))
write(fakesocket, resp)

firstmsg = Vector{UInt8}("HI.")
locked_write(fakesocket, true, OPCODE_BINARY, false, firstmsg)
emptymsg = Vector{UInt8}("")
locked_write(fakesocket, true, OPCODE_BINARY, false, emptymsg)
str1k=randstring(1024) |> Vector{UInt8}
locked_write(fakesocket, true, OPCODE_BINARY, false, str1k)
str100k=randstring(102400) |> Vector{UInt8}
locked_write(fakesocket, true, OPCODE_BINARY, false, str100k)

@testset "tests for #114" begin
@test _openstream(s, key) do ws
  @test s.stream.c.io === ws.socket.io
  @test firstmsg == read(ws)
  @test emptymsg == read(ws)
  @test str1k == read(ws)
  @test str100k == read(ws)
  close(fakesocket)
  return true
end
end