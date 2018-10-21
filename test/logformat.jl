using Logging
import Logging:default_logcolor,
                Info,
                Warn,
                Error,
                Debug,
                BelowMinLevel
using Dates
const OLDLOGGER = Logging.global_logger()
const T0_TESTS = now()

"Return file, location and time since start of test in info messages"
function custom_metafmt(level, _module, group, id, file, line)
    color = default_logcolor(level)
    prefix = (level == Warn ? "WARNING" : string(level))*':'
    suffix = ""
    # Next line was 'Info <= level <' in default_metafmt.
    # We exclude level  = Info from this early return
    Info <= level -1 < Warn && return color, prefix, suffix
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
    return color, prefix, suffix
end
const TESTLOGR = ConsoleLogger(stderr, Debug, meta_formatter = custom_metafmt)
global_logger(TESTLOGR)
@info """
    @info messages from now get a suffix.
          To reinstate the original logger:
              julia> Logging.global_logger(OLDLOGGER)
"""
nothing
