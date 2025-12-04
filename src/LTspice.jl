#__precompile__()

"Main module for `LTspice.jl` - a Julia interface to LTspice"
module LTspice
using LinearAlgebra
using StringEncodings
using Dates: DateTime
import IterTools.chain

include("open_with_unknown_encoding.jl")
include("specialarrays.jl")
include("LTspiceSimulation.jl")
include("ParseCircuitFile.jl")
include("ParseLogFile.jl")
include("ParseRawFile.jl")
include("perlineiterator.jl")
include("utility.jl")

end # module
