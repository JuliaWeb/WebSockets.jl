# This is run multiple times during testing,
# for simpler running of individual tests.
function custom_metafmt(level, _module, group, id, file, line)
    color = WebSockets.default_logcolor(level)
    prefix = string(level) * ':'
    suffix = " $(Int(round((Dates.now() - T0_TESTS).value / 1000))) s @"
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
    const T0_TESTS = Dates.now()
end

if !@isdefined TESTLOGR
    const TESTLOGR = WebSockets.WebSocketLogger(stderr, Base.CoreLogging.Debug, meta_formatter = custom_metafmt)
    WebSockets.global_logger(TESTLOGR)
end
nothing
