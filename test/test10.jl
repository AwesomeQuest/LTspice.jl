function test10()
  sim = LTspiceSimulation("test10.asc",executablepath="")
  @test LTspice.does_circuitfilearray_file_match(sim)
  show(IOBuffer(),sim)
  @test sim["m1"] == 0.0
  @test sim["bad_meas"] ≈ 1.0e200
  show(IOBuffer(),sim)
  return true
end
test10()
