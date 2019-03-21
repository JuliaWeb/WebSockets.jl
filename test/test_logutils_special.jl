# Prepare
using Revise
using Test
using Distributed
if !@isdefined LOGGINGPATH
    (@__DIR__) ∉ LOAD_PATH && push!(LOAD_PATH, @__DIR__)
    const LOGGINGPATH = realpath(joinpath(@__DIR__, "..", "logutils"))
    LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
end
using WebSockets
using logutils_ws

function takestring!(logger::WebSocketLogger)
    s = logger.stream.io|> take! |> String
    print(stdout, s)
    s
end

# Temporary function for building tests. Not nice.
import Base.-
-(s1::String, s2::String)= replace(s1, s2 =>"", count = 1)

const bwcontext = IOContext(IOBuffer())
const cocontext = IOContext(IOBuffer(), :color => true)
const bwlog = WebSocketLogger(bwcontext)
const colog = WebSocketLogger(cocontext)
const termlog = WebSocketLogger(stdout)
const nolog = WebSocketLogger(Base.DevNullStream())
const nulllog = logutils_ws.Logging.NullLogger()
const bwhd1 = "[ Info: "
const cohd1 = "\e[36m\e[1m[ \e[22m\e[39m\e[36m\e[1mInfo: \e[22m\e[39m"
const nl = "\n"
const no = "\e[0m"

@test WebSocketLogger().stream |> typeof == Base.TTY

@info "Single String logbody_s"
@test logutils_ws.logbody_s(bwcontext, "Hello") == "Hello" * nl
@test logutils_ws.logbody_s(cocontext, "Hello") == "Hello" * no * nl

@info "Two String logbody_s"
const s1 = "Kayfa ḥālak? "
const s2 = "Hawwāmtī mumtil'ah bi'anqalaysūn"
const l12 = length(s1 * s2 * nl)
@test logutils_ws.logbody_s(bwcontext, s1, s2) == s1 * s2 * nl
@test logutils_ws.termlength(logutils_ws.logbody_s(bwcontext, s1, s2)) == l12
@test logutils_ws.logbody_s(cocontext, s1, s2) == s1 * s2 * no * nl
@test logutils_ws.termlength(logutils_ws.logbody_s(stderr, s1, s2)) == l12

@info "Single String info"
with_logger(bwlog) do
       @info "Hello"
   end
@test takestring!(bwlog) ==  bwhd1 * "Hello" *nl
with_logger(()->(@info "Hello"), colog)
@test takestring!(colog) == cohd1 * "Hello" * no * nl

@info "Two String info"
with_logger(bwlog) do
       @info s1, s2
   end
@test takestring!(bwlog) ==  bwhd1 * s1 * s2 * nl
with_logger(colog) do
       @info s1, s2
   end
@test takestring!(colog) == cohd1 * s1 * s2 * no * nl

@info "Two String info, no comma"
const bwhd2 = "┌ Info: "
const cohd2 = "\e[36m\e[1m┌ \e[22m\e[39m\e[36m\e[1mInfo: \e[22m\e[39m"
const bwhdlast = "\n└   "
const cohdlast = "\n\e[36m\e[1m└ \e[22m\e[39m  "
with_logger(bwlog) do
       @info s1 s2
   end
@test takestring!(bwlog) ==  bwhd2 * s1 * bwhdlast * "s2 = \"" * s2 * "\"" * nl
with_logger(colog) do
       @info s1 s2
   end
@test takestring!(colog) == cohd2 * s1 * no * cohdlast * "s2 = \"" * s2 * "\"" * nl

@info "Paranthesis, no space after macro"
with_logger(bwlog) do
       @info(s1, s2)
   end
@test takestring!(bwlog) ==  bwhd2 * s1 * bwhdlast * "s2 = \"" * s2 * "\"" * nl

@info "Paranthesis, space after macro"
with_logger(bwlog) do
       @info (s1, s2)
   end
@test takestring!(bwlog) == bwhd1 * s1 * s2 * nl

@info "Numbers info"
with_logger(bwlog) do
       @info 10, -0.1, π
   end
@test takestring!(bwlog) ==  bwhd1 * string(10) * string(-0.1) * string(π) * nl

@info "Vectors info"
const v1 = [1,2,3]
const v2 = [4,5,6]
with_logger(bwlog) do
       @info v1, v2
   end
@test takestring!(bwlog) ==  bwhd1 * string(v1) * string(v2) * nl

@info "Time "
t() = string(Dates.Time(Dates.now()))
with_logger(bwlog) do
      @info "$(t())"
  end
@test let
    so = replace(replace(takestring!(bwlog), bwhd1 => ""), nl => "")
    Dates.Time(so) != Dates.Time("")
end

@info "No logging"
with_logger(nolog) do
       @info :time
   end
@test read(nolog.stream, 0x10) == Array{UInt8}(undef, 0)
with_logger(nulllog) do
       @info :time
   end

@info "WebSocket types logbody_s"
if !@isdefined dummyws
    dummyws(server::Bool)  = WebSocket(BufferStream(), server)
end
const dwss = dummyws(true)
const green = "\e[32m"
const yellow =  "\e[33m"
const red = "\e[31m"
const bold = "\e[1m"
@test logutils_ws.logbody_s(bwcontext, dwss.state) == "CONNECTED" * nl
@test logutils_ws.logbody_s(cocontext, dwss.state) == green * "CONNECTED" * no * no * nl
dwss.state = WebSockets.CLOSING
@test logutils_ws.logbody_s(cocontext, dwss.state) == yellow * "CLOSING" * no * no * nl
dwss.state = WebSockets.CLOSED
@test logutils_ws.logbody_s(cocontext, dwss.state) == red * "CLOSED" * no * no * nl

@info "WebSocket info"
with_logger(()->(@info dwss), colog)
@test takestring!(colog) == cohd1 * "WebSocket{BufferStream}(server, " * bold * green * "✓"  * no *
      ", " * red * "CLOSED" * no * ")" * no * nl
dwss.state = WebSockets.CLOSING
with_logger(()->(@info dwss), colog)
@test takestring!(colog) == cohd1 * "WebSocket{BufferStream}(server, " * bold * green * "✓" * no *
      ", " * yellow * "CLOSING" * no * ")" * no * nl
dwss.state = WebSockets.CLOSED
with_logger(()->(@info dwss), colog)
@test takestring!(colog) == cohd1 * "WebSocket{BufferStream}(server, " * bold * green * "✓" * no *
      ", " * red * "CLOSED" * no * ")" * no * nl
WebSockets.open((ws)->(global wss = ws), "ws://echo.websocket.org")
with_logger(()->(@info wss), colog)
@test takestring!(colog) == cohd1 * "WebSocket{TCPSocket}(client, " * bold * red * "✘" * no *
      ", " * red * "CLOSED" * no * ")" * no * nl

@info "Test than logging on separate worker process does not involve this process"
"Adds process 2, same LOAD_PATH as process 1"
function prepareworker()
    FULLLOADPATH = LOAD_PATH
    if nworkers() < 2
        addprocs(1)
    end
    @fetchfrom 2  for p in FULLLOADPATH
                            p ∉ LOAD_PATH && push!(LOAD_PATH, p)
                        end
end
prepareworker()
# This loads, but does not bring into scope.
# Which means we need full references for function calls on process 2.
@everywhere using logutils_ws
# shows that the logutils_ws isn't in scope
@fetchfrom 2 InteractiveUtils.varinfo()
@fetchfrom 2 global logr = logutils_ws.WebSocketLogger(IOContext(IOBuffer()))
@fetchfrom 2 InteractiveUtils.varinfo()
const wid = @fetchfrom 2 getpid()
const wout = @fetchfrom 2 begin
    logutils_ws.logutils_ws.with_logger(logr) do
        # This is evaluated in the calling context
        @info getpid()
        # This is evaluated in logutils_ws, we're checking it's on the same process.
        @info "$(getpid())"
    end
    String(take!(logr.stream.io))
end
const lwid1 = replace(split(wout, bwhd1)[2], nl => "")
const lwid2 = replace(split(wout, bwhd1)[2], nl => "")
@test lwid1 == lwid2
@test lwid1 == string(wid)
@test wid != string(getpid())
nothing
