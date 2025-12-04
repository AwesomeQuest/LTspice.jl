using LTspice, Test

function test17()
	sim = LTspiceSimulation(@__DIR__()*"/test17.asc",executablepath="")

	show(IOBuffer(),sim)
	@test "stepped" in flags(sim)
	@test sim["I(V1)", 2,5] == sim["I(V1)", "ψ"=>2, "Φ"=>5]
	@test length(sim["time", "Φ"=>2, "ψ"=>1]) === length(sim["I(C1)", "ψ"=>1, "Φ"=>2])
	@test sim["time", "Φ"=>2, "ψ"=>1] === sim["time", "ψ"=>1, "Φ"=>2]
	show(IOBuffer(),sim)
end
@testset test17()