using Pkg
cd(joinpath(@__DIR__, ".."))
Pkg.activate(".")
Pkg.instantiate()
using FSRU
gaps = Dict()
SILENT = false
# Autogenerate LaTeX code of Results table.
function appendtable()
    open("resultstable.txt", "a") do f # Autogenerate LaTeX code of Results table.
        print(f,
        """
        \\midrule
        $scenario_name \\\\
        \\multicolumn{1}{r}{M\\euro} &$(tot)&$(cap)&$(op)&$(fsrucost)&$(ttfcost)&$(hhcost)&$(transitcost)&$(domprodcost)\\\\
        \\multicolumn{1}{r}{bcm}&$(total_bcm_f)&-&-&$(fsruimp) &$(ttfimp) &$(hhimp)&$(transitimp) &$(domprod)\\\\"""
        )
    end
end

open("resultstable.txt", "w") do f
    print(f,
    """\\begin{table}
    \\small
    \\centering
    \\resizebox{\\textwidth}{!}{
    \\begin{tabular}{lrrrrrrrr}
\\toprule
\\textbf{Scenario} & \\textbf{Total}& \\textbf{Capex} & \\textbf{Opex} & \\textbf{FSRU}& \\textbf{LNG}& \\textbf{Producers}&\\textbf{Transit}&\\textbf{Domestic}  \\\\
& & && \\textbf{imports} & \\textbf{imports} & \\textbf{imports}& \\textbf{imports}& \\textbf{production}\\\\
"""
    )
end

begin
    scenario_num = 1
    DEMAND = "DEG"
    FSRU_USED = true  
    BROWNFIELD = false
    RUSSIA = false
    scenario_name = "Greenfield $DEMAND" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

begin
    scenario_num = 2
    DEMAND = "NZE"
    FSRU_USED = true  
    BROWNFIELD = false
    RUSSIA = false
    scenario_name = "Greenfield $DEMAND" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

begin
    scenario_num = 3
    DEMAND = "LIN"
    FSRU_USED = true  
    BROWNFIELD = false
    RUSSIA = false
    scenario_name = "Greenfield $DEMAND" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

begin
    scenario_num = 4
    DEMAND = "LIN"
    FSRU_USED = true  
    BROWNFIELD = true
    RUSSIA = false
    scenario_name = "Brownfield $DEMAND" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

begin
    scenario_num = 5
    DEMAND = "LIN"
    FSRU_USED = false
    BROWNFIELD = false
    RUSSIA = false
    scenario_name = "No-FSRU" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

begin
    scenario_num = 6
    DEMAND = "LIN"
    FSRU_USED = true
    BROWNFIELD = false
    RUSSIA = true
    scenario_name = "RUS-UKR Peace" 
    println("="^20, "\n", scenario_name, "\n", "="^20)
    include("load_sets.jl")
    include("load_params.jl")
	include("load_model.jl")
    include("run_model.jl")
    appendtable()
    include("make_plots.jl")
end

println(gaps)

# include("sensitivity.jl") # uncomment to run sensitivity analysis, warning, takes several hours.