# Note there is some type piracy going on here. This is not for general use.
# Also, modifying display might be preferable to print.
import HttpServer.Client
import HttpServer.HttpHandler
import HttpServer.Response
import HttpServer.Request
import HttpServer.Server
import HttpCommon.Cookie
import HttpCommon.Request
import HttpCommon.Response
import HttpCommon.STATUS_CODES
import URIParser.URI
import WebSockets.WebSocketHandler
import WebSockets.WebSocket
import Base.print
"Date time group string"
dtg() = Dates.format(now(), "HH:MM:SS")
"""
Console log with a heading, buffer and no mixing with output from other tasks.
We may, of course, be interrupting other tasks like stacktrace output.
"""
function clog(args...)
    buf = startbuf()
    pwc(buf, dtg(), " ", args...)
    lock(stderr)
    print(stderr, String(take!(buf)))
    unlock(stderr)
    nothing
end
"Print with 'color' arguments Base.text_colors placed anywhere. Color_normal is set after the call is finished. "
function pwc(io::IO, args...)
    for arg in args
        if isa(arg,Symbol)
            print_color(io, arg)
        else
            print(io,arg)
        end
    end
    print(io, Base.color_normal)
    nothing
end
"Type piracy on dictionaries, not nice normally"
function print(io::IO, headers::Dict{AbstractString, AbstractString})
    for pa in headers
        print(io, pa)
    end
    print(io, "\n")
    nothing
end
function print(io::IO, headers::Dict{String, Function})
    for pa in headers
        print(io, pa)
    end
    print(io, "\n")
    nothing
end

"Add color code"
print_color(io::IO, color::Symbol) = print(io, get(Base.text_colors, color, Base.color_normal))
 "Return an IO stream with colored heading and tabs"
function startbuf(prefix = "INFO:")
            buf = IOBuffer()
            pwc(buf, Base.info_color(),  :bold , prefix )
            length(prefix) > 0 && prefix[end]!= "\t" &&  print(buf, "\t")
            buf
end

"Pair print on a line with tab indent"
function print(io::IO, p::Pair)
    print(io, "\t")
    isa(p.first,Pair) && print(io, "(")
    print(io, p.first)
    isa(p.first,Pair) && print(io, ")")
    print(io, "\t=> ")
    isa(p.second,Pair) && print(io, "(")
    print(io, p.second)
    isa(p.second,Pair) && print(io, ")")
    print(io,"\n")
    nothing
end
"Print function name with reference, not nice type piracy.."
function print(io::IO, f::Function)
    show(io, f)
    print(io, "\t")
     mt = typeof(f).name.mt
     print(io, mt.defs.func.file)
     print(io, ":")
     print(io, mt.defs.func.line)
     nothing
end
"Print client"
function print(io::IO, client::Client{TCPSocket})
    pwc(io, typeof(client), " ", :bold, client.id,"\n")
    pwc(io, :cyan, "\tsock ", :bold, client.sock, "\n")
    pwc(io, :cyan, "\tparser ", :bold, client.parser.parser)
    nothing
end
"Print response"
function print(io::IO, response:: Response)
    pwc(io, :green, "\tResponse status: ", :bold, response.status," ")
    pwc(io, :green, get(STATUS_CODES, response.status, "--"), " ")
    pwc(io, :green, " Finished: ", :bold, response.finished)
    if !isempty(response.headers)
        pwc(io, :green, " Headers: ", :bold, response.headers.count)
        pwc(io, :green, " Age: ", :bold, Int(response.headers.age))
        pwc(io, :green, "\n", response.headers)
    end
    if !isempty(response.cookies)
        pwc(io, " Cookies: ", :bold, length(response.cookies))
        pwc(io, " Age: ", :bold, Int(response.headers.age))
        pwc("\n", response.cookies)
    end
    if !isempty(response.data)
        printdata(io, response.data, get(response.headers, "Content-Type","image/jpeg"))
    end
    nothing
end
"Print request"
function print(io::IO, request::Request)
    pwc(io, :cyan, :bold, "\tRequest: ", request.method, :normal, " resource ", :bold, request.resource)
    pwc(io, :cyan, "\tUri:", :bold, sprint(print, request.uri), "\n")
    if !isempty(request.headers)
        pwc(io, :cyan, "\tHeaders: ", :bold, request.headers.count, " Age: ", :bold, Int(request.headers.age))
        pwc(io, :cyan, "\n", request.headers)
    end
    if !isempty(request.data)
        printdata(io, request.data, get(request.headers, "Content-type","text/html; charset=utf-8"))
    end
    nothing
end

"Prints data, limited length"
function limlen(data)
    le= length(data)
    if le <  100
        return  String(data)
    else
        # Not sure if this is a safe way to split some types, but String should throw an error.
        return "Truncated:\n$(String(data)[1:65]).....$(String(data)[le-29:end])"
    end
end

"Indents and cleans up for printing"
function compact_format(s::String)
                    replace(s, "\r\n", "\n") |>
                    s-> replace(s, "\n\n", "\n") |>
                    s -> replace(s, "\t\t", "\t") |>
                    s -> replace(s, "\n\t", "\n") |>
                    s -> replace(s, "\n", "\n\t") |>
                    s->    startswith(s,"\t") ? s  : "\t"*s |>
                    s->    endswith(s,"\n") ? s  : s*"\n"
end
"Text data as a (truncated) repl-friendly string ."
function printdata(io::IO, data::T, contenttype::String) where T<:Array{UInt8,1}
    le = length(data)
    pwc(io, :green, "\tData length: ",  le,"\n")
    if occursin(r"^text", contenttype)
        pwc(io, :blue, data|> prettystring)
    end
end
"Text data as a (truncated) repl-friendly string ."
function prettystring(s::String)
        s|> limlen |> compact_format
end
prettystring(u::Array{UInt8,1}) = prettystring(String(u))
"Print server"
function print(io::IO, server::Server)
    pwc(io, :bold , Base.info_color(),  "Server\n")
    server.http != nothing  && print(io, server.http)
    server.websock != nothing  &&    print(io, server.websock)
end
"Print httphandler"
function print(io::IO, httphandler::HttpHandler)
    pwc(io,   :bold , Base.info_color(), "\tHttpHandler\n")
    pwc(io, :blue, :bold, "\t", :normal, "Called on opening (websocket, response):\n")
    pwc(io,  :green, "\t", httphandler.handle, "\n")
    pwc(io, "      \t", "Functions called on events:\n")
    pwc(io,  :green, httphandler.events)
    pwc(io,  "      \t", "Socket:\t", :green, httphandler.sock,"\n")
    nothing
end
"""
Print websockethandler
"""
function print(io::IO, wsh::WebSocketHandler)
    try
        pwc(io,   :bold , Base.info_color(), "\tWebSocketHandler")
        pwc(io, :blue, :bold, "\t", :normal, "Function called with (request, client):\n")
        pwc(io,  :green, "\t", wsh.handle, "\n")
    catch
    end
    nothing
end


"""
Print websocket
"""
function print(io::IO, ws::WebSocket)
    try
        pwc(io, :green, "\t", :normal, "Websocket id: ", :bold, ws.id)
        pwc(io, :green, :bold, "\t", ws.state )
        pwc(io,  "\n")
    catch
    end
    nothing
end
nothing
