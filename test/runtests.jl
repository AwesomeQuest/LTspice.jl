using LTspice
using Test
using Dates

@testset "tests not calling LTspice.exe" begin
  @testset "/test1.jl" include(@__DIR__()*"/test1.jl")
  @testset "/test2.jl" include(@__DIR__()*"/test2.jl")
  @testset "/test3.jl" include(@__DIR__()*"/test3.jl")
  @testset "/test4.jl" include(@__DIR__()*"/test4.jl")
  @testset "/test5.jl" include(@__DIR__()*"/test5.jl")
  @testset "/test6.jl" include(@__DIR__()*"/test6.jl")
  @testset "/test7.jl" include(@__DIR__()*"/test7.jl")
  @testset "/test8.jl" include(@__DIR__()*"/test8.jl")
  @testset "/test9.jl" include(@__DIR__()*"/test9.jl")
  @testset "/test10.jl" include(@__DIR__()*"/test10.jl")
  @testset "/test11.jl" include(@__DIR__()*"/test11.jl")
  @testset "/test12.jl" include(@__DIR__()*"/test12.jl")
  @testset "/test13.jl" include(@__DIR__()*"/test13.jl")
  @testset "/test14.jl" include(@__DIR__()*"/test14.jl")
  @testset "/test15.jl" include(@__DIR__()*"/test15.jl")
  @testset "/test16.jl" include(@__DIR__()*"/test16.jl")
  @testset "/test17.jl" include(@__DIR__()*"/test17.jl")
  @testset "/testinc.jl" include(@__DIR__()*"/testinc.jl")
end


is_ltspice_installed = (try LTspice.defaultltspiceexecutable() catch nothing end)!==nothing

if is_ltspice_installed
  @testset "tests calling LTspice.exe" begin
    include("localtests.jl")
  end
else
  println("LTspice.exe not found.  Skipping tests.")
end
