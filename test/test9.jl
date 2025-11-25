function test9()
  sim = LTspiceSimulation("test9.asc",executablepath="")
  @test LTspice.does_circuitfilearray_file_match(sim)
  show(IOBuffer(),sim)
  ==(measurementvalues(sim),[-0.5 -1.0 1.0; 0.0 NaN NaN; 0.5 1.0 -1.0])
#  @test measurementvalues(sim)≈[-0.5 -1.0 1.0; 0.0 NaN NaN; 0.5 1.0 -1.0]
  show(IOBuffer(),sim)
  return true
end
test9()
