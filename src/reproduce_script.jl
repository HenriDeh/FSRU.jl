using Pkg
cd(joinpath(@__DIR__, ".."))
Pkg.activate(".")
Pkg.instantiate()

DEMAND = "Ours" # Change to "NZE" or "DE Gov" to test different scenarios
BROWNFIELD = false
include("run_model.jl")
include("plotting_greenfield.jl")
BROWNFIELD = true
include("run_model.jl")
include("plotting_brownfield.jl")