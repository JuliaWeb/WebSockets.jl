#=
 TODO complete transition to using show and _show methods
 together with IOContext.
  Implement show(serverWS).
 Drop special Devices.
 Delete duplicate code.
=#

"""
Specialized logging for testing and examples in WebSockets.

To avoid type piracy, defines _show for types where specialized show methods exist,
and falls back to 'show' where they don't.

When logging to a file, it's beneficial to keep a file open during the whole logging sesssion,
since opening and closing files is so slow it may affect the sequence of things.

This module dispatches on an ad-hoc type AbstractDevice, instead of putting
additional data on an IOContext method like 'show' does. When AbstracDevice points to
Base.NullDevice(), the input arguments are processed before the call is made, but
that is all.

In Julia 0.7, current logging functionality is replaced with macros, which
can be even faster. Macros can also retrieve the current function's name without using stacktraces.
With this module, each function defines id = "thisfunction".

Methods in this file have no external dependencies. Methods with dependencies are
loaded from separate files with @require. This adds to loading time.
"""
module logutils_ws
using Dates
import Base.text_colors
import Base.color_normal
import Base.text_colors
import Base.show
include("log_http.jl")
export clog
export clog_notime
export zlog
export zlog_notime
export logto
export loggingto
export directto_abstractdevice
export AbstractDevice
export DataDispatch
export zflush

const ColorDevices = Union{Base.TTY, IOBuffer, IOContext, Base.PipeEndpoint}
const BlackWDevices = Union{IOStream, IOBuffer} # and endpoint...
const LogDevices = Union{ColorDevices, BlackWDevices, Base.DevNullStream}
abstract type AbstractDevice{T} end
struct NullDevice <: AbstractDevice{NullDevice}
        s::Base.DevNullStream
    end
struct ColorDevice{S<:ColorDevices}<:AbstractDevice{ColorDevice}
        s::S
        end
struct BlackWDevice{S<:Union{IOStream, IOBuffer}}<:AbstractDevice{BlackWDevice}
        s::S
        end
mutable struct LogDevice
        s::AbstractDevice
        end
_devicecategory(::AbstractDevice{S}) where S = S
const CURDEVICE = LogDevice(NullDevice(Base.DevNullStream()))
struct DataDispatch
    data::Array{UInt8,1}
    contenttype::String
end
"""
Redirect coming zlog calls to a stream. Default is no logging.
clog calls will duplicate to STDOUT.
"""
logto(io::ColorDevices) =  CURDEVICE.s = ColorDevice(io)
logto(io::BlackWDevices) =  CURDEVICE.s = BlackWDevice(io)
logto(io::Base.DevNullStream) =  CURDEVICE.s = NullDevice(io)

"""
Returns the current logging stream
"""
loggingto() = CURDEVICE.s.s

"""
Log to (default) nothing, or streams as given in CURDEVICE.
First argument is expected to be function id.
"""
function zlog(vars::Vararg)
    _zlog(CURDEVICE.s, vars...)
    nothing
end
"""
Log to (default) NullDevice, or the device given in CURDEVICE.
Falls back to Base.showdefault when no special methods are defined.
"""
function zlog_notime(vars::Vararg)
    _zlog_notime(CURDEVICE.s, vars...)
    nothing
end
"""
Log to the given device, but also to STDOUT if that's not the given device.
"""
function clog(vars::Vararg)
    _zlog(CURDEVICE.s, vars...)
    _devicecategory(CURDEVICE.s) != ColorDevice && _zlog(ColorDevice(stdout), vars...)
    nothing
end
"""
Log to the given device, but also to STDOUT if that's not the given device.
"""
function clog_notime(vars::Vararg)
    _zlog_notime(CURDEVICE.s, vars...)
    _devicecategory(CURDEVICE.s) != ColorDevice  && _zlog_notime(ColorDevice(stdout), vars...)
    nothing
end
"""
Flushing file write buffers, only has an effect on streams.
We do not flush automatically after every log, because that
has a relatively dramatic effect on logging speeds.
"""
zflush() = isa(CURDEVICE.s.s, IOStream) && flush(CURDEVICE.s.s)


## Below are internal functions starting with _
_zlog(::NullDevice, ::Vararg) = nothing
_zlog_notime(::NullDevice, ::Vararg) = nothing
"First argument padded and emphasized.
End the original argument list with a :normal and a new line argument."
function _zlog(d::AbstractDevice, vars::Vararg{Any,N}) where N
    if N == 1
        _log(d, :normal, _tg(), "  ", :bold, :cyan, vars[1], :normal, "\n")
    else
        lid = 26
        pads = repeat(" ", max(0, lid - length(_string(vars[1])))) #rpad don't work with color codes
        _log(d, :normal, _tg(), "  ", :bold, :cyan, vars[1], :normal, pads, vars[2:end]..., :normal, "\n")
    end
    nothing
end
"zlog, but no time stamp and no different format first argument."
function _zlog_notime(d::AbstractDevice, vars::Vararg{Any,N}) where N
    # End the original argument list with a :normal and a new line argument.
    _log(d, :bold, :cyan, vars[1:end]..., :normal, "\n")
    nothing
end
"Write to blackwdevices, inapplicable formatting neglegted. No linefeed."
function _log(bwd::BlackWDevice, vars::Vararg)
    _show.(bwd, vars)
    nothing
end

"Write colordevices. Does not reset color codes after, no linefeed."
function _log(cd::ColorDevice, vars::Vararg)
    buf = ColorDevice(IOBuffer())
    _show.(buf, vars)
    write(cd.s, take!(buf.s))
    nothing
end
"Write directly to colordevice/ IOBuffers"
function _log(cd::ColorDevice{Base.GenericIOBuffer{Array{UInt8,1}}}, vars::Vararg)
    _show.(cd, vars)
    nothing
end

"Return a string by emulating a bwdevice, where color codes are not output"
function _string(vars::Vararg)
    buf = BlackWDevice(IOBuffer())
    _show.(buf, vars)
    buf.s |> take! |> String
end



"_show takes just device and one other argument.
It falls back to normal show for nondefined _show methods."
_show(d::AbstractDevice, var) = show(d.s, var)
_show(d::AbstractDevice, s::AbstractString) = write(d.s, s);nothing

function _show(d::ColorDevice, sy::Symbol)
    co =  get(text_colors, sy, :NA)
    if co != :NA
        write(d.s, co)
    else
        write(d.s, sy)
    end
    nothing
end
function _show(d::ColorDevices, sy::Symbol)
    co =  get(text_colors, sy, :NA)
    if co != :NA
        write(d.s, co)
    else
        write(d.s, sy)
    end
    nothing
end

function _show(d::BlackWDevice, sy::Symbol)
    co =  get(text_colors, sy, :NA)
    if co == :NA
        write(d.s, ":", sy)
    end
    nothing
end

function _show(d::AbstractDevice, ex::Exception)
    _log(d, Base.warn_color(), typeof(ex), "\n")
    showerror(d.s, ex, [])
    _log(d, :normal, "\n")
end
function _show(d::AbstractDevice, err::ErrorException)
    _log(d, Base.error_color(), typeof(err), "\n")
    showerror(d.s, err, [])
    _log(d, :normal, "\n")
end
function _show(d::AbstractDevice, err::Base.IOError)
    _log(d, Base.error_color(), typeof(err), "\n")
    showerror(d.s, err, [])
    _log(d, :normal, "\n")
end



"Print dict, no heading, three pairs per line, truncate end to fit"
function _show(d::AbstractDevice, di::Dict)
    linelength = displaysize(stdout)[2]
    indent = 8
    npa = 3
    plen = div(linelength - indent, npa)
    pairs = collect(di)
    lpa = length(pairs)
    _log(d, :bold, :blue)
    for i = 1:npa:lpa
        write(d.s, " "^indent)
        write(d.s, _pairpad(pairs[i], plen))
        i+1 <= lpa   &&  write(d.s, _pairpad(pairs[i + 1], plen))
        i+2 <= lpa   &&  write(d.s, _pairpad(pairs[i + 2], plen))
        write(d.s, "\n")
    end
    _log(d, :normal)
    nothing
end
"Print array of pairs, no heading, three pairs per line, truncate end to fit"
function _show(d::AbstractDevice, pairs::Vector{Pair{SubString{String},SubString{String}}})
    linelength = 95
    indent = 8
    npa = 3
    plen = div(linelength - indent, npa)
    lpa = length(pairs)
    _log(d, :bold, :blue)
    for i = 1:npa:lpa
        write(d.s, " "^indent)
        write(d.s, _pairpad(pairs[i], plen))
        i+1 <= lpa   &&  write(d.s, _pairpad(pairs[i + 1], plen))
        i+2 <= lpa   &&  write(d.s, _pairpad(pairs[i + 2], plen))
        write(d.s, "\n")
    end
    _log(d, :normal)
    nothing
end
"Print dict, no heading, two pairs per line, truncate end to fit"
function _show(d::AbstractDevice, di::Dict{String, Function})
    linelength = 95
    indent = 8
    npa = 2
    plen = div(linelength - indent, npa)
    pairs = collect(di)
    lpa = length(pairs)
    _log(d, :bold, :blue)
    for i = 1:npa:lpa
        write(d.s, " "^indent)
        write(d.s, _pairpad(pairs[i], plen))
        i+1 <= lpa   &&  write(d.s, _pairpad(pairs[i + 1], plen))
        write(d.s, "\n")
    end
    _log(d, :normal)
    nothing
end


_pairpad(pa::Pair, plen::Int) = Base.cpad(_limlen(_string(pa), plen) , plen )
_string(pa::Pair) = _string(pa[1]) * " => " * _string(pa[2])
function _show(d::AbstractDevice, f::Function)
    mt = typeof(f).name.mt
    fnam = splitdir(string(mt.defs.func.file))[2]
    write(d.s, string(f) * " at " * fnam * ":"
        * string(mt.defs.func.line))
    nothing
end

"Type info not printed here as it is assumed the type is given by the context."
function _show(d::ColorDevice, stream::Base.LibuvStream)
    _log(d, "(", :bold, _uv_status(stream)..., :normal)
    nba = Base.nb_available(stream.buffer)
    nba > 0 && print(d.s, ", ", Base.nb_available(stream.buffer)," bytes waiting")
    print(d.s, ")")
    nothing
end

function _show(d::AbstractDevice, serv::Base.LibuvServer)
    _log(d, typeof(serv), "(", :bold, _uv_status(serv)..., :normal, ")")
    nothing
end


"Data as a truncated string"
function _show(d::AbstractDevice, datadispatch::DataDispatch)
    _showdata(d, datadispatch.data, datadispatch.contenttype)
    write(d.s, "\n")
    nothing
end


function _showdata(d::AbstractDevice, data::Array{UInt8,1}, contenttype::String)
    if occursin(r"(text|script|html|xml|julia|java)", lowercase(contenttype))
        _log(d, :green, "\tData length: ", length(data), " ", :bold, :blue)
        s = data |> String |> _limlen
        write(d.s, replace(s, r"\s+", " "))
    else
        _log(d, :green, "\tData length: ", length(data), "  ", :blue)
        write(d.s,  data |> _limlen)
    end
    nothing
end

"Truncates for logging"
_limlen(data::AbstractString) = _limlen(data, 74)
function _limlen(data::AbstractString, linelength::Int)
    le = length(data)
   if le <  linelength
        return  normalize_string(string(data), stripcc = true)
    else
        adds = " … "
        addlen = length(adds)
        truncat = 2 * div(linelength, 3)
        tail = linelength - truncat - addlen - 1
        truncstring = String(data)[1:truncat] * adds * String(data)[end-tail:end]
        return normalize_string(truncstring, stripcc = true)
    end
end
function _limlen(data::Union{Vector{UInt8}, Vector{Float64}})
    le = length(data)
    maxlen = 12 # elements, not characters
    if le <  maxlen
        return  string(data)
    else
        adds =  " ..... "
        addlen = 2
        truncat = 2 * div(maxlen, 3)
        tail = maxlen - truncat - addlen - 1
        return string(data[1:truncat])[1:end-1] * adds * string(data[end-tail:end])[7:end]
    end
end


"Time group. show() converts to string only when necessary."
_tg() = Dates.Time(now())



"For use in show(io::IO, obj) methods. Hook into this logger's dispatch mechanism."
function directto_abstractdevice(io::IO, obj)
    if isa(io, ColorDevices)
        buf = ColorDevice(IOBuffer())
    else
        buf = BlackWDevice(IOBuffer())
    end
    _show(buf, obj)
    write(io, take!(buf.s))
    nothing
end

nothing
end # module
