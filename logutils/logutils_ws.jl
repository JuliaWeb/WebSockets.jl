"""
Based directly on stdlib/ConsoleLogger, this defines a logger with
special output formatting for some types (from this and other packages).

It also adds macros based on @warn and @error in Base.CoreLogging
    @clog Log to console and the given io.
    @zlog Log to the given io.

Intended use is for processes that communicate through WebSockets.

TODO: Import and reexport from ConsoleLogger. Copy now.
------------------
ConsoleLogger(stream=stderr, min_level=Info; meta_formatter=default_metafmt,
              show_limited=true, right_justify=0)

Logger with formatting optimized for readability in a text console, for example
interactive work with the Julia REPL.

Log levels less than `min_level` are filtered out.

Message formatting can be controlled by setting keyword arguments:

* `meta_formatter` is a function which takes the log event metadata
`(level, _module, group, id, file, line)` and returns a color (as would be
passed to printstyled), prefix and suffix for the log message.  The
default is to prefix with the log level and a suffix containing the module,
file and line location.
* `show_limited` limits the printing of large data structures to something
which can fit on the screen by setting the `:limit` `IOContext` key during
formatting.
* `right_justify` is the integer column which log metadata is right justified
at. The default is zero (metadata goes on its own line).


"""
module logutils_ws
import Logging
import Logging: AbstractLogger,
                        handle_message,
                        shouldlog,
                        min_enabled_level,
                        catch_exceptions,
                        LogLevel,
                        Info,
                        Warn,
                        Error,
                        global_logger,
                        with_logger
using Base
import Base: text_colors,
            BufferStream,
            print,
            show
using Sockets
import Sockets: LibuvStream,
                LibuvServer,
                TCPSocket
import WebSockets
import WebSockets: WebSocket
export WebSocketLogger, shouldlog, current_logger_root, global_logger, with_logger

struct WebSocketLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    meta_formatter
    show_limited::Bool
    right_justify::Int
    message_limits::Dict{Any,Int}
end

function WebSocketLogger(stream::IO=stderr, min_level=Info;
                       meta_formatter=default_metafmt, show_limited=false,
                       right_justify=0)
    WebSocketLogger(stream, min_level, meta_formatter,
                  show_limited, right_justify, Dict{Any,Int}())
end

"Early filtering of events"
shouldlog(logger::WebSocketLogger, level, _module, group, id) =
    get(logger.message_limits, id, 1) > 0

"Lower bound for log level of accepted events"
min_enabled_level(logger::WebSocketLogger) = logger.min_level
"Catch exceptions during event evaluation"
catch_exceptions(logger::WebSocketLogger) = false
"Return the current logger. If stacked, find the root."
current_logger_root() =  _logger_root(Logging.current_logger())
function _logger_root(cl)
    if :previous_logger ∈ fieldnames(typeof(cl))
        return _logger_root(cl.previous_logger)
    else
        return cl
    end
end

"Handle a log event.
If the logger stream is a Base.DevNullStream, exit immediately.
Note that the appropriate use is to use Logging.DevNullLogger.
Also exit immediately if the max log limit for this id is reached."
function handle_message(logger::WebSocketLogger, level, messageargs::T, _module, group, id,
                        filepath, line; maxlog=nothing, kwargs...) where T
    if maxlog != nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end
    if logger.stream isa  Base.DevNullStream
        return
    end
    #println("Level:", level, " filepath:", filepath, " line:", line)
    # Generate a text representation of the message and all key value pairs,
    # split into lines.
    if T<: Tuple
        strbody = logbody_s(logger.stream, messageargs...)
    else
        strbody = logbody_s(logger.stream, messageargs)
    end
    msglines = [(indent=0,msg=l) for l in split(chomp(strbody), '\n')]
    #####

    dsize = displaysize(logger.stream)
    if !isempty(kwargs)
        valbuf = IOBuffer()
        rows_per_value = max(1, dsize[1]÷(length(kwargs)+1))
        valio = IOContext(IOContext(valbuf, logger.stream),
                          :displaysize=>(rows_per_value,dsize[2]-5))
        if logger.show_limited
            valio = IOContext(valio, :limit=>true)
        end
        for (key,val) in pairs(kwargs)
            showvalue(valio, val)
            vallines = split(String(take!(valbuf)), '\n')
            if length(vallines) == 1
                push!(msglines, (indent=2,msg=SubString("$key = $(vallines[1])")))
            else
                push!(msglines, (indent=2,msg=SubString("$key =")))
                append!(msglines, ((indent=3,msg=line) for line in vallines))
            end
        end
    end

    # Format lines as text with appropriate indentation and with a box
    # decoration on the left.
    color,prefix,suffix = logger.meta_formatter(level, _module, group, id, filepath, line)
    minsuffixpad = 2
    buf = IOBuffer()
    iob = IOContext(buf, logger.stream)
    nonpadwidth = 2 + (isempty(prefix) || length(msglines) > 1 ? 0 : length(prefix)+1) +
                  msglines[end].indent + termlength(msglines[end].msg) +
                  (isempty(suffix) ? 0 : length(suffix)+minsuffixpad)
    justify_width = min(logger.right_justify, dsize[2])
    if nonpadwidth > justify_width && !isempty(suffix)
        push!(msglines, (indent=0,msg=SubString("")))
        minsuffixpad = 0
        nonpadwidth = 2 + length(suffix)
    end
    for (i,(indent,msg)) in enumerate(msglines)
        boxstr = length(msglines) == 1 ? "[ " :
                 i == 1                ? "┌ " :
                 i < length(msglines)  ? "│ " :
                                         "└ "
        printstyled(iob, boxstr, bold=true, color=color)
        if i == 1 && !isempty(prefix)
            printstyled(iob, prefix, " ", bold=true, color=color)
        end
        print(iob, " "^indent, msg)
        if i == length(msglines) && !isempty(suffix)
            npad = max(0, justify_width - nonpadwidth) + minsuffixpad
            print(iob, " "^npad)
            printstyled(iob, suffix, color=:light_black)
        end
        println(iob)
    end

    write(logger.stream, take!(buf))
    nothing
end

# Formatting of values in key value pairs
showvalue(io, msg) = show(io, "text/plain", msg)
function showvalue(io, e::Tuple{Exception,Any})
    ex,bt = e
    showerror(io, ex, bt; backtrace = bt!=nothing)
end
showvalue(io, ex::Exception) = showerror(io, ex)

function default_logcolor(level)
    level < Info  ? Base.debug_color() :
    level < Warn  ? Base.info_color()  :
    level < Error ? Base.warn_color()  :
                    Base.error_color()
end

function default_metafmt(level, _module, group, id, file, line)
    color = default_logcolor(level)
    prefix = (level == Warn ? "WARNING" : string(level))*':'
    suffix = ""
    Info <= level < Warn && return color, prefix, suffix
    _module !== nothing && (suffix *= "$(_module)")
    if file !== nothing
        _module !== nothing && (suffix *= " ")
        suffix *= Base.contractuser(file)
        if line !== nothing
            suffix *= ":$(isa(line, UnitRange) ? "$(first(line))-$(last(line))" : line)"
        end
    end
    !isempty(suffix) && (suffix = "@ " * suffix)
    return color, prefix, suffix
end

"""
Length of a string as it will appear in the terminal (after ANSI color codes
are removed)
"""
function termlength(str)
    N = 0
    in_esc = false
    for c in str
        if in_esc
            if c == 'm'
                in_esc = false
            end
        else
            if c == '\e'
                in_esc = true
            else
                N += 1
            end
        end
    end
    return N
end

"""
Return the log message body string, ending with :normal (following text)
and newline.
"""
function logbody_s(context::IO, args...)
    #println("logbody s arguments ", typeof(args))
    # create a new buffer which inherits the context of context
    ioc = IOContext(IOBuffer(), context)
    _logln(ioc, args...)
    String(take!(ioc.io))
end

"""
Log the arguments to buffer io, end with newline
(and normal color if applicable).
"""
function _logln(io::IOContext, args...)
    #println("_logln arguments ", typeof(args))
    if get(io, :color, false)
        _log(io, args..., :normal, "\n")
    else
        _log(io, args..., "\n")
    end
end

"""
Log the arguments to buffer io.
"""
function _log(io::IOContext, args...)
    #println("_log arguments ", typeof(args))
    for arg in args
        #println("Going to log ", typeof(arg), arg)
        _print(io, arg)
    end
end

"""
Like 'print', avoids string
decorations, but '_print' keeps general symbol decorations.
"""
_print
"Fallback for unspecified types"
_print(io::IO, arg::Symbol) = _show(io, arg)
_print(io::IO, arg::WebSocket) = _show(io, arg)
function _print(io::IO, arg::WebSockets.ReadyState)
    arg == WebSockets.CONNECTED && _show(io, :green)
    arg == WebSockets.CLOSING && _show(io, :yellow)
    arg == WebSockets.CLOSED && _show(io, :red)
    _log(io, String(Symbol(arg)), :normal)
end
"Type info assumed given by container subtype, excluded here"
function _print(io::IO, stream::Base.LibuvStream)
    # A TCPSocket and a BufferStream are examples of LibuvStream.
    fina = fieldnames(typeof(stream))
    if :status ∈ fina
        _log(io, :bold, _uv_status(stream)..., :normal)
    elseif :is_open ∈ fina
        stream.is_open ? _log(io, :bold, :green, "✓", :normal) :  _log(io, :bold, :red, "✘", :normal)
    else
        _log(io, "status N/A")
    end
    if :buffer ∈ fina
        nba = bytesavailable(stream.buffer)
        nba > 0 && _log(io, ", in bytes: ", nba)
    end
    if :sendbuf ∈ fina
        nba = bytesavailable(stream.sendbuf)
        nba > 0 && _log(io, ", out bytes: ", nba)
    end
end
function _print(io::IO, arg)
    #println("_print fallback type ", typeof(arg), " ", arg)
    print(io, arg)
end
# TODO check TCPServer, make ServerWS and other types.

"""
Unlike _print, includes Julia decorations like ':' and '""'.
"""
_show
"If this is a color, switch, otherwise prefix by :"
function _show(io::IO, sy::Symbol)
    co =  get(text_colors, sy, "")
    if co != ""
        if get(io, :color, false)
            write(io, co)
        end
    else
        # The symbol is not a color code.
        _log(io, ":",  String(sy))
    end
end

"Fallback"
_show(io::IO, arg) = _show(io, arg)


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
include("log_ws.jl")
end
