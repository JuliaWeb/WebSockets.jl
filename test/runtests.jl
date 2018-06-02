using Base.Test
cd(Pkg.dir("WebSockets", "test"))
# WebSockets.jl
@testset "Fragment and frame unit tests" begin
    include("frametest.jl")
end

@sync yield() # avoid mixing of  output with possible deprecation warnings from .juliarc 
info("Starting test WebSockets...")

@testset "Unit test, HttpServer and HTTP handshake" begin
    include("handshaketest.jl")
end

@testset "Client-server test, HTTP client" begin
    include("client_server_test.jl")
end
@testset "Client test, HTTP client" begin
    include("client_test.jl")
end


@testset "WebSockets abrupt close & bad timing test" begin
    include("error_test.jl")
end

# TODO
# WebSockets.jl
# direct closing of tcp socket, while reading.
# closing with given reason (only from browsertests)
# unknown opcode
# Read multiple frames (use dummyws), may require change
# InterruptException
# Protocol error (not masked from client)
# writeguarded, error
# restructure browsertests
