#=
Included in logutils.jl
=#

import WebSockets.WebSocket # todo remove when including in WebSockets itself.
show(io::IO, ws::WebSocket) = directto_abstractdevice(io, ws)
function _show(d::AbstractDevice, ws::WebSocket{T}) where T
	_log(d, "WebSocket{", T, "}(")
	_log(d, ws.server ? "server, " : "client, ")
	_log(d, ws.socket, " ")
	showcompact(d.s, ws.state)
	_log(d, ")")
#	size = ws.socket.buffer.size
#	if size == 0
#		_log(d, size, " b)")
#	elseif size < 1000
#		_log(d, :yellow, size, " b)")
#	else
#		_log(d, :bold, :yellow, div(size, 1000), " kB)")
#	end
    nothing
end
@require HttpServer import WebSockets.WebSocketHandler
@require HttpServer show(io::IO, wsh::WebSocketHandler) = directto_abstractdevice(io, wsh)
@require HttpServer function _show(d::AbstractDevice, wsh::WebSocketHandler)
						_log(d,  typeof(wsh), "( " , :blue, :bold, wsh.handle, :normal, ")")
						nothing
					end

nothing