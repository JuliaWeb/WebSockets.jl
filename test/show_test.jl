mutable struct DummyStream <: Base.LibuvStream
    buffer::Base.GenericIOBuffer
    status::Int
    handle::Any
end

let kws = [], msgs =[]
    ds = DummyStream(IOBuffer(), 0, 0)
    for s = 0:9, h in [Base.C_NULL, Ptr{UInt64}(3)]
        ds.handle = h
        ds.status = s
        kwarg, msg = WebSockets._uv_status_tuple(ds)
        push!(kws, kwarg)
        push!(msgs, msg)
    end
    @test kws == [(color = :red,), (color = :blue,), (color = :red,), (color = :yellow,), (color = :red,), (color = :blue,), (color = :red,), (color = :green,), (color = :red,), (color = :green,), (color = :red,), (color = :blue,), (color = :red,), (color = :red,), (color = :red,), (color = :yellow,), (color = :red,), (color = :red,), (color = :red,), (color = :red,)]
    @test msgs == Any["null", "uninit", "invalid status", "init", "invalid status", "connecting", "invalid status", "✓", "invalid status", "active", "invalid status", "closing", "✘", "✘", "invalid status", "eof", "invalid status", "paused", "invalid status", "invalid status"]
end

let kws = [], msgs =[]
    for s in instances(WebSockets.ReadyState)
        kwarg, msg = WebSockets._uv_status_tuple(s)
        push!(kws, kwarg)
        push!(msgs, msg)
    end
    @test kws == [(color = :green,), (color = :blue,), (color = :red,)]
    @test msgs == ["CONNECTED", "CLOSING", "CLOSED"]
end

let kws = [], msgs =[]
    fi = open("temptemp", "w+")
    kwarg, msg = WebSockets._uv_status_tuple(fi)
    push!(kws, kwarg)
    push!(msgs, msg)
    close(fi)
    rm("temptemp")
    kwarg, msg = WebSockets._uv_status_tuple(fi)
    push!(kws, kwarg)
    push!(msgs, msg)
    @test kws == [(color = :green,), (color = :red,)]
    @test msgs == ["✓", "✘"]
end


fi = open("temptemp", "w+")
io = IOBuffer()
WebSockets._show(IOContext(io, :wslog=>true), fi)
close(fi)
rm("temptemp")
output = String(take!(io))
@test output == "✓"

ds = DummyStream(IOBuffer(), 0, 0x00000001)
io = IOBuffer()
WebSockets._show(io, ds)
# The handle type depends on operating system, skip that
output = join(split(String(take!(io)), " ")[2:end], " ")
# The fallback show has been used.
@test output == "uninit, 0 bytes waiting)"



udp = Sockets.UDPSocket()
bind(udp, ip"127.0.0.1", 8079)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, udp)
output = String(take!(io.io))
# No bytesavailable for UDPSocket
@test output == "\e[32m✓\e[39m"


udp = Sockets.UDPSocket()
io = IOContext(IOBuffer(), :wslog=>true)
WebSockets._show(io, udp)
output = String(take!(io.io))
# No colors in file context, correct state
@test output == "init"

bs = Base.BufferStream()
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, bs)
output = String(take!(io.io))
# No reporting of zero bytes
@test output == "\e[32m✓\e[39m"


bs = Base.BufferStream()
write(bs, "321")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, bs)
output = String(take!(io.io))
# Report bytes
@test output == "\e[32m✓\e[39m, 3 bytes"


bs = Base.BufferStream()
close(bs)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, bs)
output = String(take!(io.io))
@test output == "\e[31m✘\e[39m"


bs = Base.BufferStream()
write(bs, "321")
close(bs)
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, bs)
output = String(take!(io.io))
@test output == "\e[31m✘\e[39m, 3 bytes"


bs = Base.BufferStream()
write(bs, "123")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, ds)
output = String(take!(io.io))
# No reporting of zero bytes
@test output == "\e[34muninit\e[39m"

iob = IOBuffer()
write(iob, "123")
io = IOContext(IOBuffer(), :color => true, :wslog=>true)
WebSockets._show(io, iob)
output = String(take!(io.io))
@test output == "\e[32m✓\e[39m, 3 bytes"

iob = IOBuffer()
io = IOContext(IOBuffer())
WebSockets._show(io, iob)
output = String(take!(io.io))
@test output == "IOBuffer(data=UInt8[...], readable=true, writable=true, seekable=true, append=false, size=0, maxsize=Inf, ptr=1, mark=-1)"

io = IOContext(IOBuffer())
WebSockets._show(io, devnull)
output = String(take!(io.io))
@test output == "Base.DevNull()" || output == "Base.DevNullStream()"



# Short form, as in print(stdout, ws)
ws = WebSocket(Base.BufferStream(), true)
io = IOContext(IOBuffer())
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(server, CONNECTED)"


ws = WebSocket(Base.BufferStream(), false)
io = IOContext(IOBuffer())
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, CONNECTED)"

ws = WebSocket(Base.BufferStream(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, \e[32mCONNECTED\e[39m)"

ws = WebSocket(Sockets.TCPSocket(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, ws)
output = String(take!(io.io))
# TCPSocket is the default and not displayed.
@test output == "WebSocket(client, \e[32mCONNECTED\e[39m)"

#short form for Atom / Juno
ws = WebSocket(Sockets.TCPSocket(), false)
io = IOContext(IOBuffer(), :color => true)
show(io, "application/prs.juno.inline", ws)
output = String(take!(io.io))
@test output == "WebSocket(client, \e[32mCONNECTED\e[39m)"

# Long form, as in print(stdout, ws)
ws = WebSocket(Sockets.TCPSocket(), true)
io = IOContext(IOBuffer(), :color => true)
show(io, "text/plain", ws)
output = String(take!(io.io))
@test output == "WebSocket{TCPSocket}(server, \e[32mCONNECTED\e[39m): \e[33minit\e[39m"


ws = WebSocket(Base.BufferStream(), false)
write(ws.socket, "78")
io = IOContext(IOBuffer(), :color => true)
show(io, "text/plain", ws)
output = String(take!(io.io))
@test output == "WebSocket{BufferStream}(client, \e[32mCONNECTED\e[39m): \e[32m✓\e[39m, 2 bytes"

### For testing Base.show(ServerWS)
h(r) = HTTP.Response(200)
w(s) = nothing
io = IOBuffer()
WebSockets._show(io, h)
output = String(take!(io))
@test output == "h(r)"

WebSockets._show(io, x-> 2x)
output = String(take!(io))
@test output[1] == '#'

sws = WebSockets.ServerWS(h, w)
show(io, sws)
output = String(take!(io))
@test output == "WebSockets.ServerWS(handler=h(r), wshandler=w(s))"

sws = WebSockets.ServerWS(h, w, rate_limit=1//1)
show(io, sws)
output = String(take!(io))
@test output == "WebSockets.ServerWS(handler=h(r), wshandler=w(s), sslconfig=nothing, tcpisvalid=#1(tcp), reuseaddr=false, rate_limit=1//1, reuse_limit=$(typemax(Int)), readtimeout=0)"

sws = WebSockets.ServerWS(h, w, connection_count = Ref(2))
show(io, sws)
output = String(take!(io))
@test output == "WebSockets.ServerWS(handler=h(r), wshandler=w(s), connection_count=2)"

let chnlout, sws, sws1, sws2
    chnlout = Channel{Any}(2)
    sws = WebSockets.ServerWS(h, w; out = chnlout)
    put!(chnlout, "Errormessage")
    put!(chnlout, "stacktrace")
    io = IOBuffer()
    show(io, sws)
    output = String(take!(io))
    @test output == "WebSockets.ServerWS(handler=h(r), wshandler=w(s)).out:Channel{Any}(sz_max:2,sz_curr:2) "

    sws1 = WebSockets.ServerWS(h, w)
    sws2 = WebSockets.ServerWS(h, w)
    put!(sws1.out, "Errormessage")
    @test !isready(sws2.out)
    @test isready(sws1.out)
end
