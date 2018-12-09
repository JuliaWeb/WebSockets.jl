#=
Included in logutils_ws.jl
See TODO there.
=#

"HTTP.Response already has a show method, we're not overwriting that.
This metod is called only when logging to an Abstractdevice. The default
show method does not print binary data well as per now."
function _show(d::AbstractDevice, response::HTTP.Messages.Response)
    _log(d, :green, "Response status: ", :bold, response.status," ")
    response.status > 0 && _log(d, HTTP.Messages.STATUS_MESSAGES[response.status], " ")
    if !isempty(response.headers)
        _log(d, :green, " Headers: ", :bold, length(response.headers))
        _log(d, :green, "\n", response.headers)
    end
    if isdefined(response, :cookies)
        if !isempty(response.cookies)
            _log(d, " Cookies: ", :bold, length(response.cookies))
            _log(d, "\n", response.cookies)
        end
    end
    if !isempty(response.body)
        _log(d, "\t", DataDispatch(response.body, HTTP.header(response, "content-type", "")))
    end
    nothing
end


"HTTP.Request already has a show method, we're not overwriting that.
This metod is called only when logging to an Abstractdevice"
function _show(d::AbstractDevice, request::HTTP.Messages.Request)
    _log(d,  :normal, :light_yellow, "Request ", :normal)
    _log(d, :bold, request.method, " ", :cyan, request.target, "\n", :normal)
    if !isempty(request.body)
        _log(d, "\t", DataDispatch(request.body, HTTP.header(request, "content-type", "")))
    end
    if !isempty(request.headers)
        _log(d, "\t", :cyan, " Headers: ", length(request.headers))
        _log(d, :cyan, "\n", request.headers)
    end
    nothing
end
