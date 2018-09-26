using Test
using Pkg
#cd(Pkg.dir("WebSockets", "test"))

# Store the current logger for resetting afterwards.
using Logging # stdlib, no declared dependecy
const OLDLOGGER = Logging.global_logger
# Info suffix to include location info and time since start
include("logformat.jl")

@testset "WebSockets" begin
@info("\nFragment and unit tests\n")
@testset "Fragment and frame unit tests" begin
    include("frametest.jl");sleep(1)
end

@info("\nHTTP handshake\n")
@testset "HttpServer and HTTP handshake" begin
    include("handshaketest.jl");sleep(1)
end

@info("\nClient-server test, HTTP client\n")
@testset "Client-server test, HTTP client" begin
    include("client_server_test.jl");sleep(1)
end

@info("\nClient test, HTTP client\n")
@testset "Client test, HTTP client" begin
    include("client_test.jl");sleep(1)
end

@info("\nAbrupt close & error handling test\n")
@testset "Abrupt close & error handling test" begin
    include("error_test.jl");sleep(1)
end

@info("\n tests for server message comes first\n")
@testset "tests for server message comes first" begin
    include("serverfirst_test.jl")
end
Logging.global_logger(OLDLOGGER)
end