using Base.Test

@testset "Websockets" begin
    include("HTTP.jl")
    include("HttpServer.jl")
end