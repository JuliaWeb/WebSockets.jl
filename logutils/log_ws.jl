#=
Included in logutils_ws.jl
This can also be included without it, in which case
it defines a print format for the WebSocket and ServerWS types.
This can be included directly in Websockets.jl after testing.
=#

import Base
import Base: print,
             show,
             LibuvStream,
             BufferStream,
             text_colors

show(io::IO, ws::WebSocket) = _show(io, ws)
print(io::IO, ws::WebSocket) = _show(io, ws)

"""
Like 'print', avoids string
decorations, but '_print' keeps general symbol decorations
with the exception of color symbols in .
"""
_print

"Fallback for types not having a context definition"
function _print(io::IO, arg)
    #println("_print fallback type ", typeof(arg), " ", arg)
    print(io, arg)
end

"""
Log the arguments to buffer io, end with newline
(and color :normal).
"""
_println(io::IO, args...) = _print(io, args..., "\n", :normal)


function _print(io::IO, args...)
    for arg in args
        _print(io, arg)
    end
end
_print(io::IO, arg::Symbol) = _show(io, arg)
_print(io::IO, arg::WebSocket) = _show(io, arg)
function _print(io::IO, arg::WebSockets.ReadyState)
    arg == WebSockets.CONNECTED && _show(io, :green)
    arg == WebSockets.CLOSING && _show(io, :yellow)
    arg == WebSockets.CLOSED && _show(io, :red)
    _print(io, String(Symbol(arg)), :normal)
end

"
The context for _print(io, T) is as T in WebSocket{T}.
We don't want to define a new print format for these types in
general.
TODO consider useing IOContext for this context signalling instead.
"
function _print(io::IO, stream::Base.LibuvStream)
    # A TCPSocket and a BufferStream are subtypes of LibuvStream.
    fina = fieldnames(typeof(stream))
    if :status ∈ fina
        _print(io, :bold, _uv_status(stream)..., :normal)
    elseif :is_open ∈ fina
        stream.is_open ? _print(io, :bold, :green, "✓", :normal) :  _print(io, :bold, :red, "✘", :normal)
    else
        _print(io, "status N/A")
    end
    if :buffer ∈ fina
        nba = bytesavailable(stream.buffer)
        nba > 0 && _print(io, ", in bytes: ", nba)
    end
    if :sendbuf ∈ fina
        nba = bytesavailable(stream.sendbuf)
        nba > 0 && _print(io, ", out bytes: ", nba)
    end
end

"""
Unlike _print, includes Julia decorations like ':' and '""'.
"""
_show
"Fallback"
_show(io::IO, arg) = show(io, arg)
function _show(io::IO, ws::WebSocket{T}) where T
    _print(IOContext(io), "WebSocket{", T, "}(",
             ws.server ? "server, " : "client, ",
             ws.socket, ", ",
             ws.state, ")")
end

"If this is a color, switch, otherwise prefix by :"
function _show(io::IO, sy::Symbol)
    co =  get(text_colors, sy, "")
    if co != ""
        if get(io, :color, false)
            write(io, co)
        end
    else
        # The symbol is not a color code.
        _print(io, ":",  String(sy))
    end
end


"Return status as a tuple with color symbol and descriptive string"
function _uv_status(x)
    s = x.status
    if x.handle == Base.C_NULL
        if s == Base.StatusClosed
            return :red, "✘" #"closed"
        elseif s == Base.StatusUninit
            return :red, "null"
        end
        return :red, "invalid status"
    elseif s == Base.StatusUninit
        return :yellow, "uninit"
    elseif s == Base.StatusInit
        return :yellow, "init"
    elseif s == Base.StatusConnecting
        return :yellow, "connecting"
    elseif s == Base.StatusOpen
        return :green, "✓"   # "open"
    elseif s == Base.StatusActive
        return :green, "active"
    elseif s == Base.StatusPaused
        return :red, "paused"
    elseif s == Base.StatusClosing
        return :red, "closing"
    elseif s == Base.StatusClosed
        return :red, "✘" #"closed"
    elseif s == Base.StatusEOF
        return :yellow, "eof"
    end
    return :red, "invalid status"
end

nothing
