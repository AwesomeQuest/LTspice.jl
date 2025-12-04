# run this from test directory on a system with LTspice is_ltspice_installed
# to regenerate all of the test log files.

using LTspice

filelist = [
	@__DIR__()*"/test1.asc",
	@__DIR__()*"/test2.asc",
	@__DIR__()*"/test3.asc",
	@__DIR__()*"/test4.asc",
	@__DIR__()*"/test5.asc",
	@__DIR__()*"/test6.asc",
	@__DIR__()*"/test7.asc",
	@__DIR__()*"/test8.asc",
	@__DIR__()*"/test9.asc",
	@__DIR__()*"/test10.asc",
	@__DIR__()*"/test11.asc",
	@__DIR__()*"/test12.asc",
	@__DIR__()*"/test13.asc",
	@__DIR__()*"/test14.asc",
	@__DIR__()*"/test15.asc",
	@__DIR__()*"/test16.asc",
	@__DIR__()*"/test17.asc",
	@__DIR__()*"/testinc1.asc",
]

for file in filelist
  sim = LTspiceSimulation(file)
  run!(sim)
end

allfiles = readdir(@__DIR__(), join=true)
rm.(filter(x->occursin(".db", x), allfiles), force=true)
rm.(filter(x->occursin(".net", x), allfiles), force=true)
rm.(filter(x->occursin(".log.raw", x), allfiles), force=true)
rm.(filter(x->occursin(".op.raw", x), allfiles), force=true)