# included in handshaketests.jl
import Base.BufferStream
function templaterequests()
    chromeheaders = Dict{String, String}( "Connection"=>"Upgrade",
                                            "Upgrade"=>"websocket")
    firefoxheaders = Dict{String, String}("Connection"=>"keep-alive, Upgrade",
                                            "Upgrade"=>"websocket")
    chromerequest = HTTP.Request("GET", "/", collect(chromeheaders))
    firefoxrequest = HTTP.Request("GET", "/", collect(firefoxheaders))
    return [chromerequest, firefoxrequest]
end
convert(::Type{HTTP.Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::HTTP.Request, pa::Pair) = sethd(r, convert(HTTP.Header, pa))
sethd(r::HTTP.Request, pa::HTTP.Header) = HTTP.setheader(r, pa)

takefirstline(buf::IOBuffer) = strip(split(buf |> take! |> String, "\r\n")[1])
takefirstline(buf::BufferStream) = strip(split(buf |> read |> String, "\r\n")[1])
"""
The dummy websocket don't use TCP. Close won't work, but we can manipulate the contents
using otherwise the same functions as TCP sockets.
"""
dummyws(server::Bool)  = WebSocket(BufferStream(), server)

function dummywshandler(req, dws::WebSocket{BufferStream})
    close(dws.socket)
    close(dws)
end
function handshakeresponse(request::HTTP.Request)
    buf = BufferStream()
    c = HTTP.Connection(buf)
    t = HTTP.Transaction(c)
    s = HTTP.Stream(request, t)
    WebSockets.upgrade(dummywshandler, s)
    close(buf)
    takefirstline(buf)
end
nothing
