import Base.show
import Base.method_argnames
# Long form, as in display(ws) or REPL: ws enter
function Base.show(io::IO, ::MIME"text/plain", ws::WebSocket{T}) where T
    ioc = IOContext(io, :wslog => true)
    print(ioc, "WebSocket{", nameof(T), "}(", ws.server ? "server, " : "client, ")
    _show(ioc, ws.state)
    print(ioc, "): ")
    _show(ioc, ws.socket)
end
# Short form with state, as in print(stdout, ws)
function Base.show(io::IO, ws::WebSocket{T}) where T
    ioc = IOContext(io, :compact=>true, :wslog => true)
    if T == TCPSocket
        print(ioc, "WebSocket(")
    else
        print(ioc, "WebSocket{", nameof(T), "}(")
    end
    print(ioc, ws.server ? "server, " : "client, ")
    _show(ioc, ws.state)
    print(ioc,  ")")
end

# The default Juno / Atom display works nicely with standard output
Base.show(io::IO, ::MIME"application/prs.juno.inline", ws::WebSocket) = Base.show(io, ws)


# A Base.show method is already defined by @enum
function _show(io::IO, state::ReadyState)
    kwargs, msg = _uv_status_tuple(state)
    printstyled(io, msg; kwargs...)
end

function _show(io::IO, stream::Base.LibuvStream)
    # To avoid accidental type piracy, a double check:
    if !get(IOContext(io), :wslog, false)
        show(io, stream)
    else
        kwargs, msg = _uv_status_tuple(stream)
        printstyled(io, msg; kwargs...)
        if !(stream isa Servers.UDPSocket)
            nba = bytesavailable(stream.buffer)
            nba > 0 && print(io, ", ", nba, " bytes")
            nothing
        end
    end
end
function _show(io::IO, stream::IOStream)
    # To avoid accidental type piracy, a double check:
    if !get(IOContext(io), :wslog, false)
        show(io, stream)
    else
        kwargs, msg = _uv_status_tuple(stream)
        printstyled(io, msg; kwargs...)
    end
end
function _show(io::IO, buf::Base.GenericIOBuffer)
    # To avoid accidental type piracy, a double check:
    if !get(IOContext(io), :wslog, false)
        show(io, buf)
    else
        kwargs, msg = _uv_status_tuple(buf)
        printstyled(io, msg; kwargs...)
        nba = buf.size
        nba > 0 && print(io, ", ", nba, " bytes")
        nothing
    end
end

"For colorful printing"
function _uv_status_tuple(x)
    # adaption of base/stream.jl_uv_status_string
    s = x.status
    if x.handle == Base.C_NULL
        if s == Base.StatusClosed
            (color = :red,), "✘" #"closed"
        elseif s == Base.StatusUninit
            (color = :red,), "null"
        else
            (color = :red,), "invalid status"
        end
    elseif s == Base.StatusUninit
        (color = :blue,), "uninit"
    elseif s == Base.StatusInit
        (color = :yellow,), "init"
    elseif s == Base.StatusConnecting
        (color = :blue,), "connecting"
    elseif s == Base.StatusOpen
        (color = :green,), "✓"   # "open"
    elseif s == Base.StatusActive
        (color = :green,), "active"
    elseif s == Base.StatusPaused
        (color = :red,), "paused"
    elseif s == Base.StatusClosing
        (color = :blue,), "closing"
    elseif s == Base.StatusClosed
        (color = :red,), "✘" #"closed"
    elseif s == Base.StatusEOF
        (color = :yellow,), "eof"
    else
        (color = :red,), "invalid status"
    end
end
function _uv_status_tuple(bs::Union{Base.BufferStream, IOStream, Base.GenericIOBuffer})
    if isopen(bs)
        (color = :green,), "✓"   # "open"
    else
        (color = :red,), "✘" #"closed"
    end
end
function _uv_status_tuple(status::ReadyState)
    if status == CONNECTED
        (color = :green,), "CONNECTED"
    elseif status == CLOSING
        (color = :blue,), "CLOSING"
    elseif status == CLOSED
        (color = :red,), "CLOSED"
    end
end

### ServerWS
function Base.show(io::IO, sws::ServerWS)
    print(io, ServerWS, "(handler=")
    _show(io, sws.handler.func)
    print(io, ", wshandler=")
    _show(io, sws.wshandler.func)
    if sws.logger != stdout
        print(io, ", logger=")
        if sws.logger isa Base.GenericIOBuffer
            print(io, "IOBuffer():")
        elseif sws.logger isa IOStream
            print(io, sws.logger.name, ":")
        elseif sws.logger == devnull
        else
            print(io, nameof(typeof(sws.logger)), ":")
        end
        _show(IOContext(io, :wslog=>true), sws.logger)
    end
    if sws.options != WebSockets.ServerOptions()
        print(io, ", ")
        show(IOContext(io, :wslog=>true), sws.options)
    end
    print(io, ")")
    if isready(sws.in)
        printstyled(io, ".in:", color= :yellow)
        print(io, sws.in, " ")
    end
    if isready(sws.out)
        printstyled(io, ".out:", color= :yellow)
        print(io, sws.out, " ")
    end
end


function Base.show(io::IO, swo::WebSockets.ServerOptions)
    hidetype = get(IOContext(io), :wslog, false)
    fina = fieldnames(ServerOptions)
    hidetype || print(io, ServerOptions, "(")
    for field in fina
        fiva = getfield(swo, field)
        if fiva != nothing
            print(io, field, "=")
            print(io, fiva)
            if field != last(fina)
                print(io, ", ")
            end
        end
    end
    hidetype || print(io, ")")
    nothing
end




_show(io::IO, x) = show(io, x)
function _show(io::IO, f::Function)
   m = methods(f)
   if length(m) > 1
       print(io, f, " has ", length(m), " methods: ")
       Base.show_method_table(io, m, 4, false)
   else
       method = first(m)
       argnames = join(method_argnames(method)[2:end], ", ")
       print(io, method.name, "(", argnames, ")")
   end
end
