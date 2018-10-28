# included in handshaketests.jl

function templaterequests()
    chromeheaders = Dict{String, String}( "Connection"=>"Upgrade",
                                            "Upgrade"=>"websocket")
    firefoxheaders = Dict{String, String}("Connection"=>"keep-alive, Upgrade",
                                            "Upgrade"=>"websocket")
    chromerequest_HTTP = Request("GET", "/", collect(chromeheaders))
    firefoxrequest_HTTP = Request("GET", "/", collect(firefoxheaders))
    return [chromerequest_HTTP, firefoxrequest_HTTP]
end
convert(::Type{Header}, pa::Pair{String,String}) = Pair(SubString(pa[1]), SubString(pa[2]))
sethd(r::Request, pa::Pair) = sethd(r, convert(Header, pa))
sethd(r::Request, pa::Header) = WebSockets.HTTP.Messages.setheader(r, pa)

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
function handshakeresponse(request::Request)
    buf = BufferStream()
    c = Connection(buf)
    t = Transaction(c)
    s = Stream(request, t)
    upgrade(dummywshandler, s)
    close(buf)
    takefirstline(buf)
end
nothing
