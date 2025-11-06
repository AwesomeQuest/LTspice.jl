using LTspice
using Test
using Dates

function compare_arrays(x,y)
  @test length(x) == length(y)
  for i in eachindex(x)
    if !isnan(x[i])
      @test x[i]≈y[i]
    end
  end
  return nothing
end


@testset "tests not calling LTspice.exe" begin
  include(@__DIR__()*"/test1.jl")
  include(@__DIR__()*"/test2.jl")
  include(@__DIR__()*"/test3.jl")
  include(@__DIR__()*"/test4.jl")
  include(@__DIR__()*"/test5.jl")
  include(@__DIR__()*"/test6.jl")
  include(@__DIR__()*"/test7.jl")
  include(@__DIR__()*"/test8.jl")
  include(@__DIR__()*"/test9.jl")
  include(@__DIR__()*"/test10.jl")
  include(@__DIR__()*"/test11.jl")
  include(@__DIR__()*"/test12.jl")
  include(@__DIR__()*"/test13.jl")
  include(@__DIR__()*"/test14.jl")
  include(@__DIR__()*"/test15.jl")
  include(@__DIR__()*"/testinc.jl")
end


is_ltspice_installed = (try LTspice.defaultltspiceexecutable() catch nothing end)!=nothing

if is_ltspice_installed
  @testset "tests calling LTspice.exe" begin
    include("localtests.jl")
  end
else
  println("LTspice.exe not found.  Skipping tests.")
end
