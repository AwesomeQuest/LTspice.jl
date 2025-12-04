using LTspcie,Test

function test12()
  filename = @__DIR__()*"/test12.asc"
  # exectuablepath = null string will not run LTspice.exe.  Test parsing only.
  sim = LTspiceSimulation(filename,executablepath="")
  @test LTspice.does_circuitfilearray_file_match(sim)
  show(IOBuffer(),sim)

  v1steps = [ 1.0, 1.14869835499704, 1.31950791077289, 
              1.5157165665104, 1.74110112659225, 2.0, 
              2.29739670999407, 2.63901582154579, 3.0314331330208, 
              3.4822022531845, 4.0, 4.59479341998814, 
              5.27803164309158, 6.0628662660416, 6.964404506369, 
              8.00000000000001, 9.18958683997629, 10.5560632861832, 
              12.1257325320832, 13.928809012738, 16.0, 
              18.3791736799526, 20.0]
  bsteps = [1.0, 4.0, 7.0, 10.0]
  csteps = [4.0, 5.0, 6.0]

  @test stepvalues(sim) == (v1steps, bsteps, csteps)
  @test measurementnames(sim) == ()
  @test stepnames(sim) == ("V1","b","c")
  #@test measurementvalues(sim) == [23.0,6.0,3.0,0.0]

  @test length(collect(perlineiterator(sim))) == length(v1steps)*length(bsteps)*length(csteps)

  pli = perlineiterator(sim,header=true)
  (header,state) = iterate(pli)
  @test header == ("V1","b","c","a")
  show(IOBuffer(),sim)
  return true
end
@testset test12()
