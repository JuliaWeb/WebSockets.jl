import Base.show
# Long form, as in display(ws) or REPL ws enter
function Base.show(io::IO, ::MIME"text/plain", ws::WebSocket{T}) where T
    ioc = IOContext(io, :wslog => true)
    print(ioc, "WebSocket{", nameof(T), "}(", ws.server ? "server, " : "client, ")
    _show(ioc, ws.state)
    print(ioc, "): ")
    _show(ioc, ws.socket)
    nothing
end
# Short form, as in print(stdout, ws)
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
    nothing
end

# Short form, as in Juno / Atom
# In documentation (and possible future version)::MIME"application/prs.juno.inline"
Base.show(io::IO, ::MIME"application/prs.juno.inline", ws::WebSocket) = Base.show(io, ws)
Base.show(io::IO, ::MIME"application/juno+inline", ws::WebSocket) = Base.show(io, ws)



# A Base.show method is already defined by @enum
function _show(io::IO, state::ReadyState)
    kwargs, msg = _uv_status_tuple(state)
    printstyled(io, msg; kwargs...)
    nothing
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
        end
    end
    nothing
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
function _uv_status_tuple(bs::Base.BufferStream)
    if bs.is_open
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
