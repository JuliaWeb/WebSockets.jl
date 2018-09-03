function f1(args::T) where T
    println("f1 typeof(args) = ", typeof(args))
    isa(T, Tuple) ? f2(args...) : f2(args)
end
function f2(args::T) where T
    println("f2 typeof(args) = ", typeof(args))
    isa(T, Tuple) ? f3(args...) : f3(args)
end
function f3(args::T) where T
    println("f3 typeof(args) = ", typeof(args))
    isa(T, Tuple) ? f4(args...) : f4(args)
end
function f4(args::T) where T
    println("f4 typeof(args) = ", typeof(args))
    1
end
println(f1(2))
println(f1("Abc"))
println(f1([1,2,3]))

println(f1((2, 3)))
println(f1(("Abc", "Def")))
println(f1(([1,2,3], "Def")))


function g1(args...)
    println("g1 typeof(args) = ", typeof(args))
    g2(args...)
end
function g2(args...)
    println("g2 typeof(args) = ", typeof(args))
    g3(args...)
end
function g3(args...)
    println("g3 typeof(args) = ", typeof(args))
    g4(args...)
end
function g4(args...)
    println("g4 typeof(args) = ", typeof(args))
    1
end
function g4(arg)
    println("g4 typeof(arg) = ", typeof(arg))
    2
end
println(g1(2))
println(g1("Abc"))
println(g1([1,2,3]))

println(g1((2, 3)))
println(g1(("Abc", "Def")))
println(g1(([1,2,3], "Def")))
