using LTspice, Test

function test16()
	sim = LTspiceSimulation(@__DIR__()*"/test16.asc",executablepath="")

	show(IOBuffer(),sim)
	@test "real" in flags(sim)
	@test length(sim["time"]) == length(sim["I(C1)"])
	show(IOBuffer(),sim)
end
@testset test16()