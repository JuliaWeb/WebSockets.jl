# WebSockets.jl

[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)
[![Appveyor](https://ci.appveyor.com/api/projects/status/github/JuliaWeb/WebSockets.jl?svg=true&logo=appveyor)](https://ci.appveyor.com/project/shashi/WebSockets-jl/branch/master)


Server and client side [Websockets](https://tools.ietf.org/html/rfc6455) protocol in Julia. WebSockets is a small overhead message protocol layered over [TCP](https://tools.ietf.org/html/rfc793). It uses HTTP(S) for establishing the connections.

## Upgrading to v. 1.6
Julia 1.8.2 or higher is now required due to some instabilities. 

There are minor 'public API' changes in v. 1.6. We advise 'using' each function like below, except when experimenting.

This example tries typical 'old' code, shows errors, and shows replacement code. 

```julia
julia> using WebSockets: serve, writeguarded, readguarded, @wslog, open, 
                  HTTP, Response, ServerWS, with_logger, WebSocketLogger
julia> begin
           function handler(req)
               @wslog "Somebody wants a http response"
               Response(200)
           end
           function wshandler(ws_server)
               @wslog "A client opened this websocket connection"
               writeguarded(ws_server, "Hello")
               readguarded(ws_server)
           end
           serverWS = ServerWS(handler, wshandler)
           servetask = @async with_logger(WebSocketLogger()) do
               serve(serverWS, port = 8000)
               "Task ended"
           end
       end
[ Info: Listening on: 127.0.0.1:8000
Task (runnable) @0x000001921cbd2ca0
```

The above would work on earlier versions. But now test in a browser: [http://127.0.0.1:8000](http://127.0.0.1:8000). The browser would show: `Server never wrote a response`, and the REPL would show:

```julia
julia> [ Wslog 11:08:09.957: Somebody wants a http response
[ Wslog 11:08:10.078: Somebody wants a http response
```

We had two requests from the browser - one was for the 'favicon' of our site. But something went wrong here. If you like long stacktraces, also try ```HTTP.get("http://127.0.0.1:8000");```

__Let's revise the http handler to match the new requirements:__
```julia
julia> function handler(req)
               @wslog "HTTP.jl v1.0+ requires more of a response"
               Response(200, "Nothing to see here!")
       end
```

Reload the browser page to verify the server is updated and working!

Let us test the websockets!
```julia
julia> open("ws://127.0.0.1:8000") do ws_client
                  data, success = readguarded(ws_client)
                  if success
                      println(stderr, ws_client, " received: ", String(data))
                  end
              end;
[ LogLevel(50): A client opened this websocket connection
WebSocket(client, CONNECTED) received: Hello
```

That's it, we have upgraded by simply modifing the Response constructors. The websocket was closed at exiting the handler, and to close the running server:
```julia
julia> put!(serverWS.in, "close!")
[ Info: Server on 127.0.0.1:8000 closing
"close!"

julia> servetask
Task (done) @0x000001d6457a1180
```

Access inline documentation and have a look at the examples folder! The testing files also demonstrate a variety of uses. Benchmarks show examples of websockets and servers running on separate processes, as oposed to asyncronous tasks.

### About this package
Originally from 2013 and Julia 0.2, the WebSockets API has remained largely unchanged. It now depends on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl) for establishing the http connections. That package is in ambitious development, and most functionality of this package is already implemented directly in HTTP.jl.

This more downstream package may lag behind the latest version of HTTP.jl, and in so doing perhaps avoid some borderline bugs. This is why the examples and tests do not import HTTP methods directly, but rely on the methods imported in this package. E.g. by using `WebSockets.HTTP.listen` instead of `HTTP.listen` you may possibly be using the previous release of package HTTP. The imported HTTP version is capped so as to avoid possible issues when new versions of HTTP are released.

We aim to replace code with similar code in HTTP when possible, reducing this package to a wrapper. Ideally, all top-level tests will continue to pass without change.

## What can you do with it?
- read and write between entities you can program or know about
- serve an svg file to the web browser, containing javascript for connecting back through a websocket, adding two-way interaction with graphics
- enjoy very low latency and high speed with a minimum of edge case coding
- implement your own 'if X send this, Y do that' subprotocols. Typically,
  one subprotocol for sensor input, another for graphics or text to a display.
- use registered [websocket subprotocols](https://www.iana.org/assignments/websocket/websocket.xml#version-number) for e.g. remote controlled hardware
- relay user interaction to backend simulations
- build a network including browser clients and long-running relay servers
- use convenience functions for gatekeeping

WebSockets are well suited for user interactions via a browser or [cross-platform applications](https://electronjs.org/) like electron. Workload and development time can be moved off Julia resources, error checking code can be reduced. Preferably use websockets for passing arguments, not code, between compiled functions on both sides; it has both speed and security advantages over passing code for evaluation.

## Other tips
- Putting http handlers and websocket coroutines ('handlers') in the same process can be a security advantage. It is good practice to modify web page responses to include time-limited tokens in the address, the wsuri.
- Since `read` and `readguared` are blocking functions, you can easily end up reading indefinitely from any side of the connection. See the `close` function code for an example of non-blocking read with a timeout.
- Compression is not currenlty implemented, but easily adaptable. On local connections, there's probably not much to gain.
- If you worry about milliseconds, TCP quirks like 'warm-up' time with low transmission speed after a pause can be avoided with heartbeats. High-performance examples are missing.
- Garbage collection increases message latency at semi-random intervals, as is visible in  benchmark plots. Benchmarks should include non-memory-allocating examples.
- Time prefixes in e.g. `@wslog` are not accurate. To accurately track sequences of logging messages, include the time in your logging message, e.g. using 'time_ns()'

##### Debugging with WebSockets.ServeWS servers
Error messages from run-time are directed to a .out channel. See inline docs: ?Websockets.serve.
When using `readguarded` or `writeguarded`, errors are logged with `@debug` statements. Set the logging level of the logger you use to 'Debug', as in 'examples/count_with_logger.jl'.

##### Debugging with WebSockets.HTTP.listen servers
If you prefer to write your own server coroutine with this approach, error messages may be sent as messages to the client. This may not be good practice if you're serving pages to the internet, but very nice while developing locally. There are some inline comments in the source code which may be of help.

## Development, new features, comments
The issues section is used for planning development: Contributions are welcome.

- Version 1.6 makes necessary changes to use HTTP 1.1.0 and limits the Julia versions to 1.8.2+.
- Version 1.5 shows the current number of connections on ServerWS. ServerWS in itself is immutable.
- Version 1.4 removes a ratelimiter function.
- Version 1.3 integrates `WebSocketLogger`. It closely resembles `ConsoleLogger` from the Julia standard library. Additional features: see inline docs and 'examples/count_with_logger.jl'. With this closer integration with Julia's core logging functionality, we also introduce `@debug` statements in `readguarded` and `writeguarded` (as well as when receiving 'ping' or 'pong'). The functions still return a boolean to indicate failure, but return no reason except the logger messages.
- The /benchmark folder contain some code that is not currently working, pending logging facilities.
- Alternative Julia packages: [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) and the direct implementation in [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl).

## Errors after updating?
### To version 1.6
Updated to use HTTP 1.1.0-1.5 as a dependency.

In your code: Response(200) -> Response(200, "OK")
Also see the example at the top.

### To version 1.5.6
Updated to use HTTP 0.9 as a dependency.

### To version 1.5.2/3
Julia 0.7 is dropped from testing, but the compatibility as stated in 'Project.toml' is kept, since HTTP is also claiming to be 0.7 compatible and we do not want to put too many restraints on the compatibility graph. The non-compatibility is that @wslog will not quite work.

### To version 1.5.2
WebSockets.DEFAULTOPTIONS has changed to WebSockets.default_options()
The previous behaviour is considered a bug, and might result in
   close(s1::ServerWS) or put!(s1::ServerWS.in, "close")
also closing s2::ServerWS.

### To version 1.5.0

#### If you don't call serve(::ServerWS, etc,) but write your own code including 'listen':
The 'listen... do' syntax example is removed. You now need to wrap the handler function:
    handler(req) = WebSockets.Response(200)
    handler_wrap = WebSockets.RequestHandlerFunction(handler)

The function that accepts RequestHandlerFunction is called `handle`. It replaces `handle_request`, which was more accepting.

Consider taking keyword option values from the new function WebSockets.default_options()

#### If you call WebSockets.serve(::ServerWS, etc,):

There are no changes if you're using syntax like examples/minimal_server.jl.

Keywords 'cert' and 'key' are no longer accepted. Instead, make sure you're using the same version of MbedTLS as WebSockets.HTTP this way:
```
sslconf = WebSockets.SSLConfig(cert, key)
ServerWS(h,w, sslconfig = sslconf)
```

The upgrade to using HTTP 0.8 changes the bevaviour of server options. Try not passing any options to ServerWS. If you do, they will overrule the list of options in WebSockets.DEFAULTOPTIONS.

Type ServerOptions is removed and the corresponding fields now reside in  ServerWS.

The optional function 'tcpisvalid' used to take two arguments; it should now take only one.

Ratelimiting is now performed outside of optional user functions, if you pass keyword rate_limit ≠ nothing.

Keyword logger is no longer supported. For redirecting logs, use Logging.with_logger

### To version 1.4.0
We removed the default ratelimit! function, since the way it worked was counter-intuitive and slowed down most use cases. If you have not provided any ratelimit to SererOptions in the past, you may be able to notice a very tiny performance improvement. See issue #124 and the inline documentation.  

### To version 1.3.0
WebSockets additionaly exports WebSocketLogger, @wslog, Wslog.

### To version 1.1.0
This version is driven by large restructuring in HTTP.jl. We import more functions and types into WebSockets, e.g., WebSockets.Request. The main interface does not, intentionally, change, except for 'origin', which should now be qualified as WebSockets.origin.

### To version 0.5.0
The introduction of client side websockets to this package in version 0.5.0 may require changes in your code:
- The `WebSocket.id` field is no longer supported. You can generate unique counters by code similar to 'bencmark/functions_open_browsers.jl' COUNTBROWSER.
- You may want to modify you error handling code. Examine WebSocketsClosedError.message.
- You may want to use `readguarded` and `writeguarded` to save on error handling code.
- `Server` -> `WebSockets.WSServer`
- `WebSocketHandler` -> `WebSockets.WebsocketHandler` (or just pass a function without wrapper)
- `HttpHandler`-> `HTTP.HandlerFunction` (or just pass a function without wrapper)
- `run` -> `serve`
- `Response` -> `HTTP.Response`
- `Request` -> `HTTP.Response`

 You may also want to consider using `target`, `orgin`and `subprotocol`, which
 are compatible with both of the types above.


~~~~
::::::::::::::::
::            ::
::  Made at   ::
::            ::
::::::::::::::::
       ::
 Recurse Center
::::::::::::::::
~~~~
