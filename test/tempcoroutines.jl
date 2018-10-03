module tempcoroutines
export f
export g
using Test
function f()
    for i = 1:10
        println(stderr, "f", i)
        @test true
        yield()
    end
    throw("pj error")
    g()
end
function g()
    for i = 1:10
        println(stderr, "g", i)
        yield()
        @test true
    end
end
end
