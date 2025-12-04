# LTspice.jl

[![Build Status](https://travis-ci.org/cstook/LTspice.jl.svg?branch=master)](https://travis-ci.org/cstook/LTspice.jl)
[![Coverage Status](https://coveralls.io/repos/github/cstook/LTspice.jl/badge.svg?branch=master)](https://coveralls.io/github/cstook/LTspice.jl?branch=master)
[![Build status](https://ci.appveyor.com/api/projects/status/uf5kr5bb7xvd8wrp/branch/master?svg=true)](https://ci.appveyor.com/project/cstook/ltspice-jl/branch/master)

LTspice.jl provides a julia interface to [LTspice<sup>TM</sup>](http://www.linear.com/designtools/software/#LTspice).  Several interfaces are provided.

1. A dictionary like interface to access parameters and measurements by name.
2. An array interface, which is primarily for measurements of stepped simulations.
3. Simulations can be called like functions.

## Documentation

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://cstook.github.io/LTspice.jl/stable)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://cstook.github.io/LTspice.jl/latest)

## Installation

LTspice.jl is currently unregistered.  It can be installed using ```Pkg.clone```.
```julia
import Pkg
Pkg.add("https://github.com/AwesomeQuest/LTspice.jl.git")
```
The [julia documentation](http://docs.julialang.org) section on installing unregistered packages provides more information.

LTspice.jl is compatible with julia 1.0

## [Example 1](https://github.com/cstook/LTspice.jl/blob/master/examples/example%201/example1.ipynb)

<img src="https://github.com/cstook/LTspice.jl/blob/master/examples/example%201/example1.jpg">

Import the module.
```julia
using LTspice
```

Create an instance of LTspiceSimulation.
```julia
example1 = LTspiceSimulation("example1.asc",tempdir=true)
```

Access parameters and measurements using their name as the key.

Set a parameter to a new value.
```julia
example1["Rload"] = 20.0  # set parameter Rload to 20.0
```

Read the resulting measurement.
```julia
loadpower = example1["Pload"] # run simulation, return Pload
```

Circuit can be called like a function
```julia
loadpower = example1(100.0)  # pass Rload, return Pload
```

Use [Optim.jl](https://github.com/JuliaOpt/Optim.jl) to perform an optimization on a LTspice simulation

```julia
using Optim
result = optimize(rload -> -example1(rload)[1],10.0,100.0)
rload_for_maximum_power = example1["Rload"]
```


To get the values of a trace in a simulation like the voltage at a node simply
```julia
example1["V(n001)"]
```

These are the same names as appear in the plot pane in the LTspice app so if you name a node something like `"output"` then it would be
```julia
example1["V(output)"]
```

Similarly you can get the current through a component like a resistor like
```julia
example1["I(R1)"]
```

And you can get the time steps with 
```julia
example1["time"]
```

If the simulation is stepped like test17 in the test folder
```julia
test17 = LTspiceSimulation("test/test17.asc",tempdir=true)
```

Then you can get the step parameter names and values simply
```julia
stepnames(test17)
# ("ψ", "Φ")

stepvalues(test17)
# ([1.0e-6, 1.0e-5], [9.0e-10, 2.84604989415154e-9, 9.0e-9, 2.84604989415154e-8, 9.0e-8])
```

As well as trace names
```julia
tracenames(test17)
7-element Vector{Any}:
 "time"
 "V(output)"
 "V(input)"
 "I(V1)"
 "I(C1)"
 "I(R1)"
 "I(L1)"
```

And you can retrive either a measurement or a trace given a step value => index pair
```julia
test17["σ", "Φ" => 4, "ψ" => 2]
# 5.0e-5

test17["I(L1)", "Φ" => 4, "ψ" => 2]
#=
192-element Vector{Float32}:
  0.0
  ⋮
 -0.045786228
=#
```

You can even not specify a step and it will give you each possible option
```julia
test17["I(L1)", "Φ" => 4]
#=
2-element Vector{SubArray{Float32, 1, Matrix{Float32}, Tuple{Int64, Base.Slice{Base.OneTo{Int64}}}, true}}:
 [0.0, -5.6250955f-9, -1.7500096f-8, -6.00001f-8, -2.2000009f-7, -8.400001f-7, -3.2799999f-6, -1.2959998f-5, -3.5245375f-5, -7.416192f-5  …  -0.22722462, -0.22586831, -0.2240625, -0.2218104, -0.2195653, -0.21688215, -0.21376933, -0.21023819, -0.20630342, -0.20413218]   
 [0.0, -1.7500095f-9, -6.0000094f-9, -2.2000009f-8, -8.400001f-8, -3.28f-7, -1.2959999f-6, -5.1519996f-6, -1.4541428f-5, -3.1994794f-5  …  -0.046235647, -0.04617446, -0.046113048, -0.046060257, -0.046007346, -0.04595434, -0.045901243, -0.045856945, -0.045812603, -0.045786228]
=#
```
Notice that different traces do not necessarily have the same number of elements or time step values


## Supported Platforms

LTspice.jl works on windows and linux with LTspice under wine.  Osx is not supported.

## Additional Information

Latest documentation is [here](https://cstook.github.io/LTspice.jl/latest).

[Introduction to LTspice.jl](https://github.com/cstook/LTspice.jl/blob/master/docs/src/introduction.ipynb)

The [Linear Technology<sup>TM</sup>](http://www.linear.com) website

The [LTspice Yahoo Group](https://groups.yahoo.com/neo/groups/LTspice/info)

[LTwiki](http://www.ltwiki.org)
