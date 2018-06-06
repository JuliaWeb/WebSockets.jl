import HttpServer.Client
import HttpServer.HttpHandler
import HttpServer.Server
import HttpServer.ClientParser
import HttpServer.HttpParser
import HttpServer.Request  # Not sure if necessary, but otherwise dispatching on HttpCommon.Request can fail.
import HttpServer.Response
import HttpCommon.Cookie
import HttpCommon.STATUS_CODES
import URIParser.URI
export printstartinfo
show(io::IO, client::Client) = directto_abstractdevice(io, client)
function _show(d::AbstractDevice, client::Client)
    _log(d, typeof(client),  " id ", :bold, client.id, :normal)
    _log(d, " ", client.sock, "\n")
    _log(d, "\t\t\t", client.parser)
    nothing
end

# TODO is this good enough?
function show(io::IO, p::ClientParser)
    print(io, "HttpServer.ClientParser.HttpParser.libhttp-parser: v", HttpParser.version())
    if p.parser.http_major > 0
        print(io, " HTTP/", p.parser.http_major, ".", p.parser.http_minor)
    end
    nothing
end

"Response already has a decent show method, we're not overwriting that.
This metod is called only when logging to an Abstractdevice"
function _show(d::AbstractDevice, response::HttpServer.Response)
    _log(d, :green, "Response status: ", :bold, response.status," ")
    _log(d, get(STATUS_CODES, response.status, "--"), " ")
    if !isempty(response.headers)
        _log(d, :green, " Headers: ", :bold, response.headers.count)
        _log(d, :green, "\n", response.headers)
    end
    if !isempty(response.cookies)
        _log(d, " Cookies: ", :bold, length(response.cookies))
        _log(d, "\n", response.cookies)
    end
    if !isempty(response.data)
        _log(d, "\t", DataDispatch(response.data, get(response.headers, "Content-Type","---")))
    end
    nothing
end

"Request already has a decent show method, we're not overwriting that.
This metod is called only when logging to an Abstractdevice"
function _show(d::AbstractDevice, request::Request)
    _log(d,  :normal, :light_yellow, "Request ", :normal)
    _log(d, :bold, request.method, " ", :cyan, request.resource, "\n", :normal)
    if !isempty(request.data)
        _log(d, "\t", DataDispatch(request.data, get(request.headers, "Content-Type", "text/html; charset=utf-8")))
    end
    if request.uri != URI("")
        _log(d, :cyan, "\tUri:", :bold, _string(request.uri), :normal, "\n\t")
    end
    if !isempty(request.headers)
        _log(d, "\t", :cyan, " .headers: ", request.headers.count)
        _log(d, :cyan, "\n", request.headers)
    end
    nothing
end

"HttpServer does not define a show method for its server type. Defining this is not piracy."
show(io::IO, server::Server) = directto_abstractdevice(io, server)
function _show(d::AbstractDevice, server::Server)
    _log(d, :bold , :green,  typeof(server), "(\n", :normal)
    server.http != nothing  && _log(d, "\t", server.http)
    server.websock != nothing  && _log(d, "\t", server.websock)
    _log(d, :bold, :green, ")")
    nothing
end

"HttpServer does not define a show method for its HttpHandler type. Defining this is not piracy."
show(io::IO, httphandler::HttpHandler) = directto_abstractdevice(io, httphandler)
function _show(d::AbstractDevice, httphandler::HttpHandler)
    _log(d,  :bold, Base.info_color(), typeof(httphandler), "( " , :normal)
    _log(d,  ".handle: ", :blue, :bold, httphandler.handle, :normal, "\n")
    _log(d, "\t\t\t.events:\n")
    _log(d,  httphandler.events)
    _log(d,  "\t\t\t", ".socket:\t", httphandler.sock, :bold, Base.info_color(), ")\n")
    nothing
end

nothing