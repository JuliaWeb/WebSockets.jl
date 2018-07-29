# Included in benchmark.jl
using Distributed
using Dates
"Adds process 2, same LOAD_PATH as process 1"
function prepareworker()
    # Prepare worker
    FULLLOADPATH = LOAD_PATH
    if nworkers() < 2
        addprocs(1)
    end
    futur = @spawnat 2  for p in FULLLOADPATH
                            p ∉ LOAD_PATH && push!(LOAD_PATH, p)
                        end
    # waits for process 2 to get ready, trigger errors if any
    fetch(futur)
end

"Start and wait for async hts server"
function start_hts(timeout)
    hts_task = @async ws_hts.listen_hts()
    t1 = now() + timeout
    while now() < t1
        sleep(0.5)
        isdefined(ws_hts.TCPREF, :x) && break
    end
    if now()>= t1
        msg = " did not establish server before timeout "
        clog("start_hts", :red, msg, timeout)
        error(msg)
    end
    hts_task
end



"""
Make connection and get a reference to the HTS side of HTS-JCE connection.
Assumes a server is already running.
"""
function get_hts_jce()
    id = "get_hts_jce"
    # Make the parallel worker initiate a websocket connection to this process.
    # It will finish execution when either peer closes the connection.
    @spawnat 2  ws_jce.echowithdelay_jce()
    # async HTS will not accept the connection before we yield to it
    zlog(id, "JCE will be connecting to HTS. We ask HTS for a reference...")
    zflush()
    hts = Union{WebSocket, String}("")
    t1 = now() + TIMEOUT
    while now() < t1
        yield()
        hts = ws_hts.getws_hts()
        isa(hts, WebSocket) && break
        sleep(0.5)
    end
    return hts
end
"""
Make and get a reference to the server side of HTS-BCE websocket connection.
Will launch a different web browser every time. Returns a string
if all available browsers have been launched one time.

Assumes a server is already running.
"""
function get_hts_bce()
    id = "get_hts_jce"
    hts = Union{WebSocket, String}("")
    browser =""
    opened, browser = open_a_browser()
    # Launch the next browser in line.
    if opened
        zlog(id, "BCE in, ", browser, " will be connecting to HTS. Getting reference...")
        zflush()
        hts = Union{WebSocket, String}("")
        t1 = now() + TIMEOUT
        while now() < t1
            yield()
            hts = ws_hts.getws_hts()
            isa(hts, WebSocket) && break
            sleep(0.5)
        end
        return hts, browser
    end
    return hts, browser
end
"""
Send n messages of length messagesize HTS-JCE and back.
    -> id, serverlatencies, clientlatencies
Starts and closes a new HTS-JCE connection every function call.
In the terminology of BenchmarkTools, a call is a sample
consisting of n evaluations.
"""
function HTS_JCE(n, messagesize)
    id = "HTS_JCE"
    zlog(id, "Warming up, compiling")
    zflush()
    hts = get_hts_jce()
    if !isa(hts, WebSocket)
        msg = " could not get websocket reference"
        clog(id, msg)
        error(id * msg)
    end
    clog(id, hts)
    # Random seeding, same for all samples
    srand(1)
    clog(id, "Sending ", n, " messages of ", messagesize , " random bytes")
    sendtime = Int64(0)
    receivereplytime = Int64(0)
    sendtimes = Vector{Int64}()
    receivereplytimes =  Vector{Int64}()
    for i = 1:n
        msg = rand(0x20:0x7f, messagesize)
        sendtime = time_ns()
        write(hts, msg)
        # throw away replies
        readguarded(hts)
        receivereplytime = time_ns()
        push!(receivereplytimes, Int64(receivereplytime < typemax(Int64) ? receivereplytime : 0 ))
        push!(sendtimes,  Int64(sendtime < typemax(Int64) ? sendtime : 0 ))
    end
    #
    zlog(id, "Sending 'exit', JCE will send its time log and then exit.")
    zflush()
    write(hts, "exit")
    # We deserialize JCE's time records from this sample
    bs = Base.BufferStream()
    write(bs, read(hts))
    close(bs)
    if bytesavailable(bs) > 0
        receivetimes, replytimes = deserialize(bs)
    else
        error("Did not receive receivetimes, replytimes")
    end
    # We must read from the websocket in order for it to respond to
    # a closing message from JCE. It's also nice to yield to the async server
    # so it can exit from it's handler and release the websocket reference.
    isopen(hts) && readguarded(hts)
    yield()
    serverlatencies = receivetimes - sendtimes
    clientlatencies = receivereplytimes - replytimes
    return id, serverlatencies, clientlatencies
end
"""
Use the next browser in line, start a new HTS-BCE connection and collect n evaluations.
This is one sample.
Returns browser name and vectors with n rows:
# t1  Send 0, receive 0, measure time interval
# t2  Send 0, receive 0 twice, measure time interval
# t3  Send x, receive 0, measure time interval
# t4  Send x, receive 0, receive x, measure time interval
"""
function HTS_BCE(n, x)
    id = "HTS_BCE"
    zlog(id)
    zflush()
    msg = ""
    (hts, browser) = get_hts_bce()
    if browser == ""
        msg = "Could not find and open more browser types"
    elseif !isa(hts, WebSocket)
        msg = " could not get ws reference from " * browser * " via HTS"
    end
    if msg != ""
        clog(id, msg)
        return "", Vector{Int}(), Vector{Int}(), Vector{Int}(), Vector{Int}()
    end
    clog(id, hts)
    # Random seeding, same for all samples
    srand(1)
    clog(id, "Sending ", n, " messages of ", x , " random bytes")
    st1 = UInt64(0)
    st2 = UInt64(0)
    rt1 = UInt64(0)
    rt2 = UInt64(0)
    rt3 = UInt64(0)
    rt4 = UInt64(0)

    t1 =  Vector{Int}()
    t2 =  Vector{Int}()
    t3 =  Vector{Int}()
    t4 =  Vector{Int}()

    for i = 1:n
            # Send empty message, measure time after two empty replies
            msg = Vector{UInt8}()
            st1 = time_ns()
            write(hts, msg)
            read(hts)
            rt1 = time_ns()
            read(hts)
            rt2 = time_ns()

            # Send message, measure time after one empty and one echoed replies
            msg = rand(0x20:0x7f, x)
            st2 = time_ns()
            write(hts, msg)
            # throw away replies. We expect a sequence per sent message:
            # two empty messages, then the original content.
            read(hts)
            rt3 = time_ns()
            read(hts)
            rt4 = time_ns()
            # Store time intervals
            push!(t1, Int(rt1 - st1))
            push!(t2, Int(rt2 - st1))
            push!(t3, Int(rt3 - st2))
            push!(t4, Int(rt4 - st2))
    end
    #
    zlog(id, "Close websocket")
    close(hts)
    # Also yield to the server task so it can release it's reference.
    sleep(1)
    # Return browser name and measured time interval vectors [ns]
    browser, t1, t2, t3, t4
end

"
Constant message size [b], measured time interval vectors [ns]
    -> server and client speeds, server and client bandwidth [ns/b]
"
function serverandclientspeeds(messagesize, serverlatencies, clientlatencies)
    serverspeeds =  serverlatencies / messagesize
    clientspeeds =  clientlatencies / messagesize
    n = length(serverspeeds)
    serverbandwidth = sum(serverlatencies) / (n * messagesize)
    clientbandwidth = sum(clientlatencies) / (n * messagesize)
    serverspeeds, clientspeeds, serverbandwidth, clientbandwidth
end


"
Measured time interval vectors [ns] -> client and server speeds, bandwidth [ns/b]
x is message size [b].
"
function serverandclientspeeds_indirect(x, t1, t2, t3, t4)
    # assuming a measured time interval consists of
    # t(x) = t0s + t0c + a*x + b*x
    # where
    # t(x)      measured time at the server
    # t0s       initial serverlatency, for a "zero length" message
    # t0c       initial clientlatency, for a "zero length" message
    # x         message length [b]
    # a         marginal server speed [ns/b]
    # b         marginal client speed [ns/b]
    #
    #
    # t1 = t0s +  t0c              Send 0, receive 0, measure t1
    # t2 = t0s + 2t0c              Send 0, receive 0 twice, measure t2
    # t3 = t0s +  t0c + a*x        Send x, receive 0, measure t3
    # t4 = t0s + 2t0c + a*x + b*x  Send x, receive 0, receive x, measure t4
    #
    # hence,
    t0s =  2t1 - t2
    t0c = -t1 + t2
    a = (- t1   + t3) / x
    b =   (t1 - t2  - t3 + t4) / x
    # Drop the marginal speed info, return effective speeds
    # serverspeeds = (t0s + a*x) / x
    # clientspeeds = (t0s + a*x) / x
    serverspeeds = t0s / x + a
    clientspeeds = t0c / x + b
    n = length(serverspeeds)
    serverbandwidth = sum(serverspeeds) / n
    clientbandwidth = sum(clientspeeds) / n
    return serverspeeds, clientspeeds, serverbandwidth, clientbandwidth
end


## Note that the shorthand plot functions below require input symbols
## that are defined at module-level (not in a local scope)

"Generate a time series lineplot"
lp(sy::Symbol) = lineplot(collect(1:length(eval(sy))), eval(sy), title = String(sy), width = displaysize(stdout)[2]-20, canvas = AsciiCanvas)


"Generate a vector of time series lineplots with a common title prefix"
function lp(symbs::Vector{Symbol}, titleprefix)
    map(symbs) do sy
        pl = lp(sy)
        title!(pl, titleprefix * " " * title(pl))
    end
end

"Generate an x-y lineplot in REPL"
function lp(syx::Symbol, syy::Symbol)
    lpl = lineplot(eval(syx), eval(syy), title = String(syy), width = displaysize(stdout)[2]-20, canvas = AsciiCanvas)
    xlabel!(lpl, String(syx))
end

"Generate a vector of x-y lineplots with a common title prefix"
function lp(syxs::Vector{Symbol}, syys::Vector{Symbol}, titleprefix)
    map(zip(syxs, syys)) do pair
        pl = lp(pair[1], pair[2])
        title!(pl, titleprefix * " " * title(pl))
    end
end

"Generate an x-y scatterplot"
function sp(syx::Symbol, syy::Symbol)
    spl = scatterplot(eval(syx), eval(syy), title = String(syy), width = displaysize(stdout)[2]-15, canvas = DotCanvas)
    xlabel!(spl, String(syx))
end