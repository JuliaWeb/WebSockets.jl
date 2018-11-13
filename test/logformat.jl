# This is run multiple times during testing,
# for simpler running of individual tests.
using Logging
import Logging: default_logcolor,
                Info,
                Warn,
                Error,
                Debug,
                BelowMinLevel,
                shouldlog
import Base.CoreLogging.catch_exceptions
import Test.TestLogger
import WebSockets.HTTP.Servers
using Dates
if !@isdefined OLDLOGGER
    const OLDLOGGER = Logging.global_logger()
    const T0_TESTS = now()
end
"Return file, location and time since start of test in info and warn messages"
function custom_metafmt(level, _module, group, id, file, line)
    color = default_logcolor(level)
    prefix = string(level) * ':'
    suffix = ""

    # Next line was 'Info <= level <' in default_metafmt.
    # We exclude level  = [Info , Warn ] from this early return
    Info <= level -1 < Warn - 1 && return color, prefix, suffix
    _module !== nothing && (suffix *= "$(_module)")
    if file !== nothing
        _module !== nothing && (suffix *= " ")
        suffix *= Base.contractuser(file)
        if line !== nothing
            suffix *= ":$(isa(line, UnitRange) ? "$(first(line))-$(last(line))" : line)"
        end
        suffix *= " $(Int(round((now() - T0_TESTS).value / 1000))) s"
    end
    !isempty(suffix) && (suffix = "@ " * suffix)
    # Reduce the visibility / severity of the most irritating messages from package HTTP
    # This has no effect, really, because they are disabled through 'shouldlog' below.
    if group == "Servers"
        color = :grey
        suffix = "\t\t" * suffix
    end
    return color, prefix, suffix
end

function shouldlog(::ConsoleLogger, level, _module, group, id)
    if _module == Servers
        if level == Warn || level == Info
            return false
        else
            return true
        end
    else
        return true
    end
end
catch_exceptions(::ConsoleLogger) = false
if !@isdefined TESTLOGR
    const TESTLOGR = ConsoleLogger(stderr, Debug, meta_formatter = custom_metafmt)
    global_logger(TESTLOGR)
    @info("""
        @info and @warn messages from now get a suffix, @debug
        \t\tmessages are shown. Warning and info messages from HTTP.Servers
        \t\tare suppressed.
    """)
end
nothing
