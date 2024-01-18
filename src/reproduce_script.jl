using Pkg
cd(@__DIR__)
Pkg.activate(".")
Pkg.instantiate()

include("model_greenfield.jl")
include("plotting_greenfield.jl")
include("model_brownfield.jl")
include("plotting_brownfield.jl")