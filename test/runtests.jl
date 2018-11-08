using Test
# Info suffix to include location info and time since start
include("logformat.jl")
# This won't work in Juno, which resets at every new evaluation.
@info "Logger format"
@testset "WebSockets" begin
printstyled(color=:blue, "\nFragment and unit\n")
@testset "Fragment and unit" begin
    @test true
   include("frametest.jl");sleep(1)
end
printstyled(color=:blue, "\nHandshake\n")
@testset "HTTP handshake" begin
    include("handshaketest.jl");sleep(1)
end

printstyled(color=:blue, "\nClient_listen\n")
@testset "Client_listen" begin
    include("client_listen_test.jl");sleep(1)
end

printstyled(color=:blue, "\nClient_serverWS\n")
@testset "Client_serverWS" begin
    include("client_serverWS_test.jl");sleep(1)
end

printstyled(color=:blue, "\nClient test, HTTP client\n")
@testset "Client test, HTTP client" begin
#    include("client_test.jl");sleep(1)
end

printstyled(color=:blue, "\nAbrupt close & error handling\n")
@testset "Abrupt close & error handling" begin
   include("error_test.jl");sleep(1)
end
if !@isdefined(OLDLOGGER)
    Logging.global_logger(OLDLOGGER)
end
end
