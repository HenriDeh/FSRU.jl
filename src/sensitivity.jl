SILENT = true
# Run base values
DEMAND = "LIN"
FSRU_USED = true  
BROWNFIELD = false
RUSSIA = false
scenario_name = "Greenfield $DEMAND" 

println("="^20, "\nRunning sensitivity, comparing to ", scenario_name, "\n", "="^20)
include("load_sets.jl")
include("load_params.jl")
include("load_model.jl")
set_silent(model)
include("run_model.jl")
base_plan = round.(Int, value.(port_upgrade))
println("Base plan:")
for (c,n) in port_dict 
    println(c*"($n)" => round.(Int, base_plan[n,:])')
end

println("="^20, "Price sensitivity")
price_scale_range = 0.5:0.025:1.5
installed_capacity_price = Int[]
for scale in price_scale_range
    print(scale, " ")
    include("load_sets.jl")
    include("load_params.jl")
    global price_fsru *= scale
    for c in keys(country_price)
        if c ∉ ("NO", "DK", "DE")
            country_price[c] .*= scale
        end
    end
    include("load_model.jl")
    set_silent(model)
    include("run_model.jl")
    push!(installed_capacity_price, round(sum(value.(sum(port_upgrade[p,:])*fsru_per_port[p]*5) for p in port_set)))
end

###########################################################
println("="^20, "Investment sensitivity")

investment_scale_range = 0.5:0.05:1.5
installed_capacity_investment = Int[]
for scale in investment_scale_range
    print(scale, " ")
    include("load_sets.jl")
    include("load_params.jl")
    global infra_capex = Dict(p => scale*1.228*((fsru_per_port[p]*80+30)*1.1+54) for p in port_set)
    global total_capex = Dict(p => sum(infra_capex[p]/investment_horizon/(1 + (1-r))^t for t in 1:investment_horizon) + pipeline_capex[p] for p in port_set)
    global port_opex = Dict(p => 0.025*(infra_capex[p])/max(1,fsru_per_port[p]) + lease_cost for p in port_set) # opex per fsru in use
	include("load_model.jl")
    set_silent(model)
    include("run_model.jl")
    push!(installed_capacity_investment, round(sum(value.(sum(port_upgrade[p,:])*fsru_per_port[p]*5) for p in port_set)))
end

###########################################################
println("="^20, "Lease sensitivity")

lease_scale_range = 0.7:0.1:1.8
installed_capacity_lease = Int[]
for scale in lease_scale_range
    print(scale, " ")
    include("load_sets.jl")
    include("load_params.jl")
    global lease_cost *= scale
    global port_opex = Dict(p => 0.025*(infra_capex[p])/max(1,fsru_per_port[p]) + lease_cost for p in port_set) # opex per fsru in use
	include("load_model.jl")
    set_silent(model)
    include("run_model.jl")
    push!(installed_capacity_lease, round(sum(value.(sum(port_upgrade[p,:])*fsru_per_port[p]*5) for p in port_set)))
end

###########################################################
println("="^20, "Horizon sensitivity")

global changed = false
include("load_sets.jl")
include("load_params.jl")
investment_horizon = length(periods)
total_capex = Dict(p => sum(infra_capex[p]/investment_horizon/(1 + (1-r))^t for t in 1:investment_horizon) + pipeline_capex[p] for p in port_set)
include("load_model.jl")
set_silent(model)
include("run_model.jl")
global changed = !(all(round.(Int, value.(port_upgrade)) .== base_plan))
if changed
    println("Plan changes at horizon = $investment_horizon, upgrades:")
    for (c,n) in port_dict 
        println(c*"($n)" => round.(Int,value.(port_upgrade)[n,:])')
    end
else
    println("No change with horizon = $investment_horizon")
end

###########################################################
println("="^20, "Discount sensitivity")

discount_range = 0.0025:0.01:0.1
installed_capacity_discount = Int[]
for discount in discount_range
    print(discount, " ")
    include("load_sets.jl")
    include("load_params.jl")
    global r = (1-discount)
    global infra_capex = Dict(p => 1.228*((fsru_per_port[p]*80+30)*1.1+54) for p in port_set)
    global total_capex = Dict(p => sum(infra_capex[p]/investment_horizon/(1 + (1-r))^t for t in 1:investment_horizon) + pipeline_capex[p] for p in port_set)
    global port_opex = Dict(p => 0.025*(infra_capex[p])/max(1,fsru_per_port[p]) + lease_cost for p in port_set) # opex per fsru in use
	include("load_model.jl")
    set_silent(model)
    include("run_model.jl")
    push!(installed_capacity_discount, round(sum(value.(sum(port_upgrade[p,:])*fsru_per_port[p]*5) for p in port_set)))
end
begin
fsensitivity = Figure(size = (1200, 300));
ys = round.(price_scale_range.* 100)
ax1 = Axis(fsensitivity[1,1], title = "Price sensitivity", limits =(extrema(ys), (0, 60)), xticks = ys[begin:4:end] , xlabel = "Scale factor (%)", ylabel = "Installed FSRU capacity (bcm)")
lines!(ax1, ys, installed_capacity_price, color = :black)
vlines!(ax1, [100], linestyle = (:dash, :loose), color = :black)

ys = round.(investment_scale_range.* 100)
ax2 = Axis(fsensitivity[1,2], title = "Investment cost sensitivity", limits =(extrema(ys), (0, 60)), xticks = ys[begin:2:end], xlabel = "Scale factor (%)", ylabel = "Installed FSRU capacity (bcm)")
lines!(ax2, ys, installed_capacity_investment, color = :black)
vlines!(ax2, [100], linestyle = (:dash, :loose), color = :black)

ys = round.(lease_scale_range.* 100)
ax3 = Axis(fsensitivity[1,3], title = "Lease sensitivity", limits =(extrema(ys), (0, 60)), xticks = ys[begin:1:end], xlabel = "Scale factor (%)", ylabel = "Installed FSRU capacity (bcm)")
lines!(ax3, ys, installed_capacity_lease, color = :black)
vlines!(ax3, [100], linestyle = (:dash, :loose), color = :black)

# ys = ((1 .- discount_range) .* 100)
# ax4 = Axis(fsensitivity[1,4], title = "Discount sensitivity", limits =(extrema(ys), (0, 60)), xticks = ys, xlabel = "Scale factor (%)", ylabel = "Installed FSRU capacity (bcm)")
# lines!(ax4, ys, installed_capacity_discount, color = :black)
# vlines!(ax4, [0.0175*100], linestyle = (:dash, :loose), color = :black)

linkyaxes!(ax1, ax2, ax3)#, ax4)
save("sensitivity.png", fsensitivity)
end