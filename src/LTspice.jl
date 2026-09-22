#__precompile__()

"Main module for `LTspice.jl` - a Julia interface to LTspice"
module LTspice
using LinearAlgebra
using StringEncodings
using Dates: DateTime
import IterTools.chain

include("simulation/open_with_unknown_encoding.jl")
include("simulation/specialarrays.jl")
include("simulation/LTspiceSimulation.jl")
include("simulation/ParseCircuitFile.jl")
include("circuit/SymbolDefinitions.jl")
include("circuit/EditCircuit.jl")
include("circuit/CircuitTopology.jl")
include("simulation/ParseLogFile.jl")
include("simulation/perlineiterator.jl")
include("simulation/utility.jl")
include("simulation/ParseRawFile.jl")

end # module
