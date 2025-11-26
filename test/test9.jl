function test9()
  sim = LTspiceSimulation("test9.asc",executablepath="")
  @test LTspice.does_circuitfilearray_file_match(sim)
  show(IOBuffer(),sim)
  @test ==(measurementvalues(sim),[-0.5 -1.0 1.0; 0.0 1e+200 -1e+200; 0.5 1.0 -1.0])
  show(IOBuffer(),sim)
  return true
end
test9()
