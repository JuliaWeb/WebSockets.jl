import Logging: Info,
                default_logcolor,
                min_enabled_level,
                shouldlog,
                handle_message,
                termlength,
                showvalue

import Base.CoreLogging: logmsg_code,
                @_sourceinfo,
                _min_enabled_level,
                current_logger_for_env,
                logging_error
import Base.string_with_env
const Wslog = LogLevel(50)
"""
Differences to stdlib/Logging/ConsoleLogger:

    - default timestamp on logging messages (except @info)
    - a 'shouldlog' function can be passed in. The `shouldlog_default` function filters
        on HTTP.Servers messages as well as on message_limits
    - :wslog => true flag which may be used for context-sensitive output
        from 'show' methods. This means a user can define 'show' methods
        which are used with this logger without affecting the behaviour
        defined in other modules.
    - :limited => true is included in the default IOContext. Keyword: show_limited
    - string_with_env_ws is exported for easy overloading on specific types
    - @info, @debug, @warn etc. will splat the first argument if it's a tuple arguments, e.g.

    julia> var = "a"
    "a"
    julia> @info (1, var)
    [ Info: 1a


"""
struct WebSocketLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    meta_formatter
    show_limited::Bool
    right_justify::Int
    message_limits::Dict{Any,Int}
    shouldlog::Function
end
function WebSocketLogger(stream::IO=stderr, min_level=Info;
                       meta_formatter = default_metaformat, show_limited=true,
                       right_justify=0, shouldlog = shouldlog_default)
    WebSocketLogger(stream, min_level, meta_formatter,
                  show_limited, right_justify, Dict{Any,Int}(), shouldlog)
end

"Defines a default logging message format with timestamp"
function default_metaformat(level, _module, group, id, file, line)
    color = default_logcolor(level)
    if level == Wslog
        # Message generated with @wslog
        prefix = "Wslog $(Dates.Time(now())):"
        return color, prefix, ""
    elseif level == Info
        return color, string(level) * ':', ""
    else
        prefix = string(level) * ':'
        suffix = "$(Dates.Time(now())) @ "
        _module !== nothing && (suffix *= "$(_module)")
        if file !== nothing
            _module !== nothing && (suffix *= " ")
            suffix *= Base.contractuser(file)
            if line !== nothing
                suffix *= ":$(isa(line, UnitRange) ? "$(first(line))-$(last(line))" : line)"
            end
        end
        return color, prefix, suffix
    end
end

"Redirects to function that can be passed in when defining logger"
function shouldlog(logger::WebSocketLogger, level, _module, group, id)
    logger.shouldlog(logger::WebSocketLogger, level, _module, group, id)
end

"Early filtering of messages based on message id limits, silencing of HTTP.Servers if defined"
function shouldlog_default(logger::WebSocketLogger, level, _module, group, id)
    _module == WebSockets.HTTP.Servers && return false
    return get(logger.message_limits, id, 1) > 0
end

"Immutable lower bound for log level of accepted events."
min_enabled_level(logger::WebSocketLogger) = logger.min_level


"This is a copy of stdlib / Logging.ConsoleLogger's handle message function,
with the exceptions

    1) adding  :wslog=>true to the IOContext
    2) passing IOContext while converting message to strings
    3) evaluate Tuple message arguments without showing paranthesis and commas "
function handle_message(logger::WebSocketLogger, level, message, _module, group, id,
                        filepath, line; maxlog=nothing, kwargs...)
    if maxlog != nothing && maxlog isa Integer
        remaining = get!(logger.message_limits, id, maxlog)
        logger.message_limits[id] = remaining - 1
        remaining > 0 || return
    end

    # Generate a text representation of the message and all key value pairs,
    # split into lines.
    msgpretty = string_with_env_ws(logger.stream, message)
    msglines = [(indent=0,msg=l) for l in split(chomp(msgpretty), '\n')]
    dsize = displaysize(logger.stream)
    if !isempty(kwargs)
        valbuf = IOBuffer()
        rows_per_value = max(1, dsize[1]÷(length(kwargs)+1))
        valio = IOContext(IOContext(valbuf, logger.stream),
                          :displaysize => (rows_per_value,dsize[2]-5),
                          :limit => logger.show_limited,
                          :wslog=>true)
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

"""
Context-aware text representation of the first argument to logging macros.
Made easily available for overloading on specific types.
"""
function string_with_env_ws(env, xs::Tuple)
    s = ""
    if isempty(xs)
        return s
    end
    for x in xs
        s *= string_with_env_ws(env, x)
    end
    return s
end
string_with_env_ws(env, x) = string_with_env(env, x)


macro  wslog(exs...) logmsg_code((@_sourceinfo)..., Wslog,  exs...) end
