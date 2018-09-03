#=
Included in logutils_ws.jl
=#
print(io::IO, ws::WebSocket) = _show(io, ws)
show(io::IO, ws::WebSocket) = _show(io, ws)
function _show(io::IO, ws::WebSocket{T}) where T
    #println(stderr, "in _show websocket")
    _log(IOContext(io), "WebSocket{", T, "}(",
             ws.server ? "server, " : "client, ",
             ws.socket, ", ",
             ws.state, ")")
end

nothing
