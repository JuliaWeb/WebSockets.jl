using Base.Test
cd(Pkg.dir("WebSockets", "test"))

@sync yield() # avoid mixing of  output with possible deprecation warnings from .juliarc

@testset "WebSockets" begin
@info("\nFragment and unit tests\n")
@testset "Fragment and frame unit tests" begin
    include("frametest.jl");sleep(1)
end

@info("\nHttpServer and HTTP handshake\n")
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

end
# TODO
# restructure browsertests
