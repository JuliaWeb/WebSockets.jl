# included in runtests.jl
# The first test set is an close adaption of /stdlib/Logging/test/runtests.jl
# The second test set checks additional functionality
using Test
using WebSockets
import WebSockets: Logging
import Logging: min_enabled_level, shouldlog, handle_message, with_logger
import Base.CoreLogging: Info,
                         Debug,
                         Warn,
                         Error,
                         LogLevel

@noinline func1() = backtrace()

@testset "WebSocketLogger" begin
    # First pass log limiting
    @test min_enabled_level(WebSocketLogger(devnull, Debug)) == Debug
    @test min_enabled_level(WebSocketLogger(devnull, Error)) == Error

    # Second pass log limiting
    logger = WebSocketLogger(devnull)
    @test shouldlog(logger, Info, Base, :group, :asdf) === true
    handle_message(logger, Info, "msg", Base, :group, :asdf, "somefile", 1, maxlog=2)
    @test shouldlog(logger, Info, Base, :group, :asdf) === true
    handle_message(logger, Info, "msg", Base, :group, :asdf, "somefile", 1, maxlog=2)
    @test shouldlog(logger, Info, Base, :group, :asdf) === false

    # Check that maxlog works without an explicit ID (#28786)
    buf = IOBuffer()
    io = IOContext(buf, :displaysize=>(30,80), :color=>false)
    logger = WebSocketLogger(io)
    # This covers an issue (#28786) in stdlib/Julia v 0.7, where log_record_id is not defined
    # in the expanded macro. Fixed Nov 2018, labelled for backporting to v1.0.0
    if VERSION >= v"1.0.0"
        with_logger(logger) do
            for i in 1:2
                @info "test" maxlog=1
            end
        end
        @test String(take!(buf)) ==
        """
        [ Info: test
        """
        with_logger(logger) do
            for i in 1:2
                @info "test" maxlog=0
            end
        end
        @test String(take!(buf)) == ""
    end
    @testset "Default metadata formatting" begin
        @test Logging.default_metafmt(Debug, Base, :g, :i, expanduser("~/somefile.jl"), 42) ==
            (:blue,      "Debug:",   "@ Base ~/somefile.jl:42")
        @test Logging.default_metafmt(Info,  Main, :g, :i, "a.jl", 1) ==
            (:cyan,      "Info:",    "")
        @test Logging.default_metafmt(Warn,  Main, :g, :i, "b.jl", 2) ==
            (:yellow,    "Warning:", "@ Main b.jl:2")
        @test Logging.default_metafmt(Error, Main, :g, :i, "", 0) ==
            (:light_red, "Error:",   "@ Main :0")
        # formatting of nothing
        @test Logging.default_metafmt(Warn,  nothing, :g, :i, "b.jl", 2) ==
            (:yellow,    "Warning:", "@ b.jl:2")
        @test Logging.default_metafmt(Warn,  Main, :g, :i, nothing, 2) ==
            (:yellow,    "Warning:", "@ Main")
        @test Logging.default_metafmt(Warn,  Main, :g, :i, "b.jl", nothing) ==
            (:yellow,    "Warning:", "@ Main b.jl")
        @test Logging.default_metafmt(Warn,  nothing, :g, :i, nothing, 2) ==
            (:yellow,    "Warning:", "")
        @test Logging.default_metafmt(Warn,  Main, :g, :i, "b.jl", 2:5) ==
            (:yellow,    "Warning:", "@ Main b.jl:2-5")
    end

    function dummy_metafmt(level, _module, group, id, file, line)
        :cyan,"PREFIX","SUFFIX"
    end

    # Log formatting
    function genmsg(message; level=Info, _module=Main,
                    file="some/path.jl", line=101, color=false, width=75,
                    meta_formatter=dummy_metafmt, show_limited=true,
                    right_justify=0, kws...)
        buf = IOBuffer()
        io = IOContext(buf, :displaysize=>(30,width), :color=>color)
        logger = WebSocketLogger(io, Debug,
                               meta_formatter=meta_formatter,
                               show_limited=show_limited,
                               right_justify=right_justify)
        Logging.handle_message(logger, level, message, _module, :a_group, :an_id,
                               file, line; kws...)
        String(take!(buf))
    end

    # Basic tests for the default setup
    @test genmsg("msg", level=Info, meta_formatter=Logging.default_metafmt) ==
    """
    [ Info: msg
    """
    @test genmsg("line1\nline2", level=Warn, _module=Base,
                 file="other.jl", line=42, meta_formatter=Logging.default_metafmt) ==
    """
    ┌ Warning: line1
    │ line2
    └ @ Base other.jl:42
    """
    # Full metadata formatting
    @test genmsg("msg", level=Debug,
                 meta_formatter=(level, _module, group, id, file, line)->
                                (:white,"Foo!", "$level $_module $group $id $file $line")) ==
    """
    ┌ Foo! msg
    └ Debug Main a_group an_id some/path.jl 101
    """

    @testset "Prefix and suffix layout" begin
        @test genmsg("") ==
        replace("""
        ┌ PREFIX EOL
        └ SUFFIX
        """, "EOL"=>"")
        @test genmsg("msg") ==
        """
        ┌ PREFIX msg
        └ SUFFIX
        """
        # Behavior with empty prefix / suffix
        @test genmsg("msg", meta_formatter=(args...)->(:white, "PREFIX", "")) ==
        """
        [ PREFIX msg
        """
        @test genmsg("msg", meta_formatter=(args...)->(:white, "", "SUFFIX")) ==
        """
        ┌ msg
        └ SUFFIX
        """
    end

    @testset "Metadata suffix, right justification" begin
        @test genmsg("xxx", width=20, right_justify=200) ==
        """
        [ PREFIX xxx  SUFFIX
        """
        @test genmsg("xxx\nxxx", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        └ xxx         SUFFIX
        """
        # When adding the suffix would overflow the display width, add it on
        # the next line:
        @test genmsg("xxxx", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxxx
        └             SUFFIX
        """
        # Same for multiline messages
        @test genmsg("""xxx
                        xxxxxxxxxx""", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        └ xxxxxxxxxx  SUFFIX
        """
        @test genmsg("""xxx
                        xxxxxxxxxxx""", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        │ xxxxxxxxxxx
        └             SUFFIX
        """
        # min(right_justify,width) is used
        @test genmsg("xxx", width=200, right_justify=20) ==
        """
        [ PREFIX xxx  SUFFIX
        """
        @test genmsg("xxxx", width=200, right_justify=20) ==
        """
        ┌ PREFIX xxxx
        └             SUFFIX
        """
    end

    # Keywords
    @test genmsg("msg", a=1, b="asdf") ==
    """
    ┌ PREFIX msg
    │   a = 1
    │   b = "asdf"
    └ SUFFIX
    """
    # Exceptions shown with showerror
    @test genmsg("msg", exception=DivideError()) ==
    """
    ┌ PREFIX msg
    │   exception = DivideError: integer division error
    └ SUFFIX
    """

    # Attaching backtraces
    bt = func1()
    @test startswith(genmsg("msg", exception=(DivideError(),bt)),
    """
    ┌ PREFIX msg
    │   exception =
    │    DivideError: integer division error
    │    Stacktrace:
    │     $(VERSION < v"1.6" ? "" : " ")[1] func1()""")


    @testset "Limiting large data structures" begin
        @test genmsg("msg", a=fill(1.00001, 100,100), b=fill(2.00002, 10,10)) ==
        """
        ┌ PREFIX msg
        │   a =
        │    100×100 $(Matrix{Float64}):
        │     1.00001  1.00001  1.00001  1.00001  …  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     ⋮                                   ⋱                    $(VERSION < v"1.1" ? "       " : "")
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │   b =
        │    10×10 $(Matrix{Float64}):
        │     2.00002  2.00002  2.00002  2.00002  …  2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     ⋮                                   ⋱                    $(VERSION < v"1.1" ? "       " : "")
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        └ SUFFIX
        """
        # Limiting the amount which is printed
        @test genmsg("msg", a=fill(1.00001, 10,10), show_limited=false) ==
        """
        ┌ PREFIX msg
        │   a =
        │    10×10 $(Matrix{Float64}):
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        └ SUFFIX
        """
    end

    # Basic colorization test
    @test genmsg("line1\nline2", color=true) ==
    """
    \e[36m\e[1m┌ \e[22m\e[39m\e[36m\e[1mPREFIX \e[22m\e[39mline1
    \e[36m\e[1m│ \e[22m\e[39mline2
    \e[36m\e[1m└ \e[22m\e[39m\e[90mSUFFIX\e[39m
    """

end

@testset "WebSocketLogger_special" begin
    # Log formatting
    function spec_msg(message; level=Info,
                    color = false,
                    shouldlog = WebSockets.shouldlog_default)
        buf = IOBuffer()
        io = IOContext(buf, :color => color)
        logger = WebSocketLogger(io, Debug,
                               shouldlog = shouldlog)
        with_logger(logger) do
                if level == Info
                    @info message
                elseif level == Wslog
                    @wslog message
                elseif level == Warn
                    @warn message
                elseif level == Debug
                    @debug message
                else
                    @error message
                end
            end
        String(take!(buf))
    end

    # Normal info
    @test spec_msg("---") == "[ Info: ---\n"

    # Debug, own format
    msg = spec_msg("---", level = Debug)
    @test startswith(msg, "┌ Debug: ---\n└ ")
    @test '@' in msg

    # Loglevel Wslog, own format
    # This covers an issue related to #28786 in stdlib/Julia v 0.7, where log_record_id is not defined
    # in the expanded macro. Why it is triggered here, but not in the LogLevel Info test is unknown.
    if VERSION >= v"1.0.0"
        msg = spec_msg("---", level = Wslog)
        @test startswith(msg, "[ Wslog ")
        @test endswith(msg, ": ---\n")
    end
    # Blocking all log levels except Wslog.
    spec_shouldlog(logger, level, _module, group, id) = level == Wslog
    # Issue 28786
    if VERSION >= v"1.0.0"
        msg = spec_msg("---", level = Wslog, shouldlog = spec_shouldlog)
        @test startswith(msg, "[ Wslog ")
        @test endswith(msg, ": ---\n")
    end
    @test spec_msg("---", shouldlog = spec_shouldlog) == ""
    @test spec_msg("---", level = Debug, shouldlog = spec_shouldlog) == ""
    @test spec_msg("---", level = Warn, shouldlog = spec_shouldlog) == ""
    @test spec_msg("---", level = Error, shouldlog = spec_shouldlog) == ""

    # Check two lines output for all except log level Info and Wslog
    @test startswith(spec_msg("---", level = Debug), "┌ Debug: ---\n└ ")
    @test startswith(spec_msg("---", level = Warn), "┌ Warn: ---\n└ ")
    @test startswith(spec_msg("---", level = Error), "┌ Error: ---\n└ ")

    # Check colors in first argument show methods are preserved
    ws = WebSocket(IOBuffer(), true)
    @test spec_msg(ws) == "[ Info: WebSocket{GenericIOBuffer}(server, CONNECTED)\n"
    @test spec_msg(ws, color= true) == "\e[36m\e[1m[ \e[22m\e[39m\e[36m\e[1mInfo: \e[22m\e[39mWebSocket{GenericIOBuffer}(server, \e[32mCONNECTED\e[39m)\n"

    # Check tuples in first argument, resembling println(arg1, arg2)
    @test spec_msg(("Now testing ", ws), color=true) == "\e[36m\e[1m[ \e[22m\e[39m\e[36m\e[1mInfo: \e[22m\e[39mNow testing WebSocket{GenericIOBuffer}(server, \e[32mCONNECTED\e[39m)\n"

    # Check tuples in first argument, resembling println(arg1, arg2)
    @test spec_msg(("Now testing ", ws), color=true) == "\e[36m\e[1m[ \e[22m\e[39m\e[36m\e[1mInfo: \e[22m\e[39mNow testing WebSocket{GenericIOBuffer}(server, \e[32mCONNECTED\e[39m)\n"

    # Check default shouldlog filters away WebSockets. HTTP.Servers, i.e. HTTP.Servers
    logger = WebSocketLogger()
    @test shouldlog(logger, Info, WebSockets.HTTP.Servers, :group, :asdf) == false
    @test shouldlog(logger, Info, Main, :group, :asdf) == true

    # Check that error handling works with @wslog
    if VERSION >= v"1.0.0"
        # This covers an issue (#28786) in stdlib/Julia v 0.7, where log_record_id is not defined
        # in the expanded macro. Fixed Nov 2018, labelled for backporting to v1.0.0
        buf = IOBuffer()
        io = IOContext(buf, :displaysize=>(30,80), :color=>true)
        logger = WebSocketLogger(io)
        with_logger(logger) do
               @wslog sqrt(-2)
               end
       @test length(String(take!(buf))) > 1900
       """
       [ Info: test
       """
   end
end
nothing
