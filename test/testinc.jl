function testinc1()
  sim = LTspiceSimulation(@__DIR__()*"/testInc1.asc",executablepath="",tempdir=true)
  @test ~LTspice.does_circuitfilearray_file_match(sim) # because of includes in temp directory
  show(IOBuffer(),sim)
  @test measurementnames(sim) == ("incA","incB","incC","incD","incE","incF")
  return true
end
testinc1()
