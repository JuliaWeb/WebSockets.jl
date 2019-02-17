# This is run multiple times during testing,
# for simpler running of individual tests.
import WebSockets
import WebSockets:  Logging,
                    WebSocketLogger,
                    Dates.now,
                    global_logger,
                    default_logcolor

function custom_metafmt(level, _module, group, id, file, line)
    color = default_logcolor(level)
    prefix = string(level) * ':'
    suffix = " $(Int(round((now() - T0_TESTS).value / 1000))) s @"
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

if !@isdefined OLDLOGGER
    const OLDLOGGER = WebSockets.global_logger()
    const T0_TESTS = now()
end

if !@isdefined TESTLOGR
    const TESTLOGR = WebSocketLogger(stderr, Base.CoreLogging.Debug, meta_formatter = custom_metafmt)
    global_logger(TESTLOGR)
end
nothing
