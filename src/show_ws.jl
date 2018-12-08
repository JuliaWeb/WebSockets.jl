import Base.show
# Long form, as in display(ws) or REPL ws enter
function Base.show(io::IO, ::MIME"text/plain", ws::WebSocket{T}) where T
    ioc = IOContext(io, :wslog => true)
    print(ioc, "WebSocket{", nameof(T), "}(", ws.server ? "server, " : "client, ")
    show(ioc, ws.state)
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
        print(ioc, "WebSocket{", nameof(T), "}(", ws.server ? "server, " : "client, ")
    end
    print(ioc, ws.server ? "server, " : "client, ")
    show(ioc, ws.state)
    print(ioc,  ")")
    nothing
end
# The following does not seem to get called by Atom. Fallback is the long form.
# Base.show(io::IO, ws::WebSocket, ::MIME"application/prs.juno.inline") = print(io, "Juno! Atom!")


function Base.show(io::IO, state::ReadyState)
    kwargs, msg = _uv_status_tuple(state)
    printstyled(io, msg; kwargs...)
    nothing
end
function _show(io, stream)
    @warn("_show fallback!")
    show(io, stream)
end
function _show(io::IO, stream::Base.LibuvStream)
    # To avoid accidental type piracy, a double check:
    if !get(IOContext(io), :wslog, false)
        show(io, stream)
    else
        kwargs, msg = _uv_status_tuple(stream)
        printstyled(io, msg; kwargs...)
        if !(typeof(stream) isa Sockets.UDPSocket)
            nba = bytesavailable(stream.buffer)
            nba > 0 && print(io, ", ", nba, " bytes waiting")
        end
    end
    nothing
end
# adaption of base/stream.jl_uv_status_string
function _uv_status_tuple(x)
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
        (color = :yellow,), "uninit"
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
function _uv_status_tuple(status::ReadyState)
    s = string(status)
    if s == "CONNECTED"
        (color = :green,), s
    elseif s == "CLOSING"
        (color = :blue,), s
    elseif s == "CLOSED"
        (color = :red,), s
    else
        (color = :red,), "invalid status"
    end
end
