using Test
import Base:    C_NULL, LibuvStream, GenericIOBuffer, BufferStream
import Sockets: UDPSocket, @ip_str, send, recvfrom, TCPSocket

using WebSockets

import WebSockets:_show,
    ReadyState,
    _uv_status_tuple,
    Response
mutable struct DummyStream <: LibuvStream
    buffer::GenericIOBuffer
    status::Int
    handle::Any
end


let kws = [], msgs =[]
    ds = DummyStream(IOBuffer(), 0, 0)
    for s = 0:9, h in [C_NULL, Ptr{UInt64}(3)]
        ds.handle = h
        ds.status = s
        kwarg, msg = _uv_status_tuple(ds)
        push!(kws, kwarg)
        push!(msgs, msg)
    end
    @test kws == [(color = :red,), (color = :blue,), (color = :red,), (color = :yellow,), (color = :red,), (color = :blue,), (color = :red,), (color = :green,), (color = :red,), (color = :green,), (color = :red,), (color = :blue,), (color = :red,), (color = :red,), (color = :red,), (color = :yellow,), (color = :red,), (color = :red,), (color = :red,), (color = :red,)]
    @test msgs == Any["null", "uninit", "invalid status", "init", "invalid status", "connecting", "invalid status", "✓", "invalid status", "active", "invalid status", "closing", "✘", "✘", "invalid status", "eof", "invalid status", "paused", "invalid status", "invalid status"]
end

let kws = [], msgs =[]
    for s in instances(ReadyState)
        kwarg, msg = _uv_status_tuple(s)
        push!(kws, kwarg)
        push!(msgs, msg)
    end
    @test kws == [(color = :green,), (color = :blue,), (color = :red,)]
    @test msgs == ["CONNECTED", "CLOSING", "CLOSED"]
end

let kws = [], msgs =[]
    fi = open("temptemp", "w+")
    kwarg, msg = _uv_status_tuple(fi)
    push!(kws, kwarg)
    push!(msgs, msg)
    close(fi)
    rm("temptemp")
    kwarg, msg = _uv_status_tuple(fi)
    push!(kws, kwarg)
    push!(msgs, msg)
    @test kws == [(color = :green,), (color = :red,)]
    @test msgs == ["✓", "✘"]
end


fi = open("temptemp", "w+")
io = IOBuffer()
_show(IOContext(io, :wslog=>true), fi)
close(fi)
rm("temptemp")
output = String(take!(io))
@test output == "✓"

ds = DummyStream(IOBuffer(), 0, 0x00000001)
io = IOBuffer()
_show(io, ds)
# The handle type depends on operating system, skip that
output = join(split(String(take!(io)), " ")[2:end], " ")
# The fallback show has been used.
@test output == "uninit, 0 bytes waiting)"



udp = UDPSocket()
bind(udp, ip"127.0.0.1", 8079)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, udp)
output = String(take!(io.io))
# No bytesavailable for UDPSocket
@test output == "\e[32m✓\e[39m"


udp = UDPSocket()
io = IOContext(IOBuffer(), :wslog=>true)
_show(io, udp)
output = String(take!(io.io))
# No colors in file context, correct state
@test output == "init"

bs = BufferStream()
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, bs)
output = String(take!(io.io))
# No reporting of zero bytes
@test output == "\e[32m✓\e[39m"


bs = BufferStream()
write(bs, "321")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, bs)
output = String(take!(io.io))
# Report bytes
@test output == "\e[32m✓\e[39m, 3 bytes"


bs = BufferStream()
close(bs)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, bs)
output = String(take!(io.io))
@test output == "\e[31m✘\e[39m"


bs = BufferStream()
write(bs, "321")
close(bs)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, bs)
output = String(take!(io.io))
@test output == "\e[31m✘\e[39m, 3 bytes"


bs = BufferStream()
write(bs, "123")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, ds)
output = String(take!(io.io))
# No reporting of zero bytes
@test output == "\e[34muninit\e[39m"

iob = IOBuffer()
write(iob, "123")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
_show(io, iob)
output = String(take!(io.io))
@test output == "\e[32m✓\e[39m, 3 bytes"

iob = IOBuffer()
io = IOContext(IOBuffer())
_show(io, iob)
output = String(take!(io.io))
@test output == "IOBuffer(data=UInt8[...], readable=true, writable=true, seekable=true, append=false, size=0, maxsize=Inf, ptr=1, mark=-1)"

io = IOContext(IOBuffer())
_show(io, devnull)
output = String(take!(io.io))
@test output == "Base.DevNull()" || output == "Base.DevNullStream()"



# Short form, as in print(stdout, ws)
ws = WebSocket(BufferStream(), true)
io = IOContext(IOBuffer())
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(server, CONNECTED)"


ws = WebSocket(BufferStream(), false)
io = IOContext(IOBuffer())
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, CONNECTED)"

ws = WebSocket(BufferStream(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, \e[32mCONNECTED\e[39m)"

ws = WebSocket(TCPSocket(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, ws)
output = String(take!(io.io))
# TCPSocket is the default and not displayed.
@test output == "WebSocket(client, \e[32mCONNECTED\e[39m)"

#short form for Atom / Juno
ws = WebSocket(TCPSocket(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, "application/prs.juno.inline", ws)
output = String(take!(io.io))
@test output == "WebSocket(client, \e[32mCONNECTED\e[39m)"

# Long form, as in print(stdout, ws)
ws = WebSocket(TCPSocket(), true)
io = IOContext(IOBuffer(), :color => true)
show(io, "text/plain", ws)
output = String(take!(io.io))
@test output == "WebSocket{TCPSocket}(server, \e[32mCONNECTED\e[39m): \e[33minit\e[39m"


ws = WebSocket(BufferStream(), false)
write(ws.socket, "78")
io = IOContext(IOBuffer(), :color => true)
show(io, "text/plain", ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, \e[32mCONNECTED\e[39m): \e[32m✓\e[39m, 2 bytes"

### For testing Base.show(ServerWS)
h(r) = Response(200)
w(ws, r) = nothing
io = IOBuffer()
_show(io, h)
output = String(take!(io))
@test output == "h(r)"

_show(io, x-> 2x)
output = String(take!(io))
@test output[1] == '#'


sws = ServerWS(h, w)
show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r))"

sws = ServerWS(h, w,  ratelimit = 1 // 1)
show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), readtimeout=180.0, ratelimit=1//1, support100continue=true, logbody=true)"

# with loggers
sws = ServerWS(handler= h, wshandler= w, logger = stderr)
io = IOBuffer()
show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=TTY:✓)" ||
    output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=PipeEndpoint():✓)" ||
    output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=PipeEndpoint:✓)"
fi = open("temptemp", "w+")
sws = ServerWS(h, w, fi)
io = IOBuffer()
_show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=<file temptemp>:✓)"
close(fi)
_show(io, sws)
rm("temptemp")
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=<file temptemp>:✘)"


sws = ServerWS(handler= h, wshandler= w, logger = devnull)
io = IOBuffer()
show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=Base.DevNull())" ||
    output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=Base.DevNullStream())"

sws = ServerWS(handler= h, wshandler= w, logger = IOBuffer())
io = IOBuffer()
show(io, sws)
output = String(take!(io))
@test output == "ServerWS(handler=h(r), wshandler=w(ws, r), logger=IOBuffer():✓)"
