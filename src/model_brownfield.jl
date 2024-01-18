using FSRU, Distances, JuMP

ports_coordinates = Dict(["Mukran" => (13.644526, 54.512157),"Wilhelmshaven" => (8.108275, 53.640799), "Brunsbüttel" => (9.175174, 53.888166), "Lubmin" => (13.648727, 54.151454), "Stade" => (9.506341, 53.648904), "Emden" => (7.187397, 53.335209), "Rostock" => (12.106811, 54.098095), "Lubeck" => (10.685321, 53.874815), "Bremerhaven" => (8.526210, 53.593061), "Hambourg" => (9.962496, 53.507492), "Duisburg" => (6.739063, 51.431325)])

g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict  = create_graph(ports_coordinates)

##Sets 
begin
    periods = 1:length(2023:2050)
    node_set = vertices(g)
    arc_dict = Dict(i => (e.src, e.dst) for (i,e) in enumerate(edges(g)))
    arc_set = values(arc_dict)
    bidirectional_arc_set = Set(a for a in arc_set if get_prop(g, a..., :is_bidirectional)==1)
    for a in bidirectional_arc_set
        pop!(bidirectional_arc_set, (a[2], a[1]))
    end
    consumers_set = values(consumers_dict)
    domestic_set = values(domestic_dict)
    port_set = Set(values(port_dict))
    export_set = values(export_dict)
    import_set = values(import_dict)
    export_countries_set = Dict{String, Vector{Int}}()
    for n in export_set
        c = get_prop(g, n, :country) 
        if haskey(export_countries_set, c)
            push!(export_countries_set[c], n)
        else
            export_countries_set[c] = [n]
        end
    end
    import_countries_set = Dict{String, Vector{Int}}() 
    for n in import_set
        c = get_prop(g, n, :country)
        if haskey(import_countries_set, c)
            push!(import_countries_set[c], n)
        else
            import_countries_set[c] = [n]
        end
    end
    fsru_set = 1:12
    demand_nodes_set = union(Set(domestic_set), Set(consumers_set))
    supply_nodes_set = union(Set(port_set), Set(import_set))
end
##Parameters 
begin
    γ = 0.99
    demand_multiplier = range(start = 1, stop = 0, length = length(periods)+1)[2:end]
    arc_capacity = Dict([a => get_prop(g, a..., :capacity_Mm3_per_d)*365/1000 for a in arc_set]) #bcm3 per year
    arc_bidirectional = Dict([a => get_prop(g, a..., :is_bidirectional) for a in arc_set])
    arc_length = Dict(a => get_prop(g, a..., :length_km) for a in arc_set)
    flow_cost = 0. #2.64e-5 #M€/km/bcm
    ##Supply
    #import    
    countries_supply = Dict("BE" => 26.58, "AT" => 0.39, "NO" => 49.24, "CZ" => 11.96, "CH" => 1.69, "FR" => 0.42, "PL" => 0.3, "DK" => 0.001, "NL" => 26.15, "FI" => 0.) #bcm3 per year
    price_fsru = 35.29*9769444.44/1e6 #ACER EU spot price [EUR/MWh] converted to M€/bcm (avg 31/03 -> 31/12 2023)
    price_ttf = price_fsru + 2.89*9769444.44/1e6 #add ACER TTF benchmark, converted (avg 31/03 -> 31/12 2023)
    price_hh = 2.496*35315000*1.0867/1e6 #$/mmbtu (US EIA) converted to M€/bcm (US EIA) (avg 04 -> 12 2023)
    country_price = Dict("BE" => price_ttf, "AT" => price_hh, "NO" => price_hh, "CZ" => price_hh, "CH" => price_hh, "FR" => price_ttf, "PL" => price_hh, "DK" => price_hh, "NL" => price_ttf, "FI" => 0.)
    total_import = sum(values(countries_supply))
    #ports
    fsru_per_port = Dict(port_set .=> 1); 
    fsru_per_port[port_dict["Wilhelmshaven"]] = 2
    new_pipeline_length = Dict(node => haversine(ports_coordinates[city], get_prop(g,node,:coordinates))/1000 for (city, node) in port_dict) #km
    investment_horizon = 10
    pipeline_cost_per_km = 0.3  #(capex + opex, depends on diameter) #M€
    total_capex = 1000 - new_pipeline_length[port_dict["Wilhelmshaven"]]*pipeline_cost_per_km*fsru_per_port[port_dict["Wilhelmshaven"]]
    port_capex = fill(sum(total_capex/investment_horizon/(1 + (1-γ))^t for t in 1:investment_horizon), length(periods)) #[sum((960/(length(periods)-t+1))*(γ^(k-t)) for k in periods if k >= t) for t in periods] #net present value of capex in t
    port_opex = 0.02*total_capex #opex per fsru in use
    #FSRUs
    fsru_cap = Dict(fsru_set .=> 5) #bcm per year
    #all
    total_supply = sum(values(countries_supply))
    ##Demand
    #export
    countries_demand = Dict("BE" => 0., "AT" => 8.03, "LU" => 0., "CZ" => 29.57, "CH" => 3.36, "FR" => 1.37, "PL" => 3.76, "FI" => 0., "DK" => 2.17, "NL" => 2.77) #bcm3 per year 
    total_export = sum(values(countries_demand))                                                  
    #domestic
    TOTAL_DEMAND = 86.7 #(2022)
    total_domestic_demand = 0.59*TOTAL_DEMAND #bcm3 per year
    PERCENTAGE_SATISFIED = sum(get_prop(g, n, :gdp_percentage) for n in domestic_set)
    nodal_domestic_demand = Dict(n => get_prop(g, n, :gdp_percentage)*total_domestic_demand*1/PERCENTAGE_SATISFIED for n in domestic_set)
    #industrial
    total_industrial_demand = 0.41*TOTAL_DEMAND #bcm3 per year
    nodal_industrial_demand = Dict(n => get_prop(g, n, :demand_percentage)*total_industrial_demand for n in consumers_set)
    #all demand 
    nodal_demand = merge(nodal_domestic_demand, nodal_industrial_demand)
    println("total supply (imports) = $total_supply\ntotal demand = $TOTAL_DEMAND\ntotal exports = $total_export\nleaving ", TOTAL_DEMAND + total_export - total_supply, " of capacity needed")
end
##Model
begin
    model = Model(HiGHS.Optimizer)
    @variables model begin 
        port_upgrade[port_set,periods], Bin
        port_upgraded[port_set,periods], Bin
        assign_fsru_to_port[port_set, fsru_set,periods], Bin
        0 <= arc_flow[i in arc_set, periods] 
        0 <= import_flow[import_set, periods]
        0 <= export_flow[export_set, periods]
        0 <= fsru_flow[port_set,periods]
    end
    @constraints model begin
        #demand satisfaction and flow conservation
        c_demand_flow[node in setdiff(demand_nodes_set, port_set), t in periods],
            sum(arc_flow[(src, node),t] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst),t] for dst in outneighbors(g, node)) + nodal_demand[node]*demand_multiplier[t]
        #demand satisfaction and flow conservation at ports
        c_demand_flow_port[node in port_set,t in periods],
                fsru_flow[node,t] + sum(arc_flow[(src, node),t] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst),t] for dst in outneighbors(g, node)) + nodal_demand[node]*demand_multiplier[t]
        #fsru port capacity
        c_fsru_port_capacity[p in port_set,t in periods],
            fsru_flow[p,t] <= sum(assign_fsru_to_port[p, f, t]*fsru_cap[f] for f in fsru_set)
        #import flow
        c_import_flow[node in setdiff(import_set,export_set),t in periods],
            import_flow[node,t] + sum(arc_flow[(src, node),t] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst),t] for dst in outneighbors(g, node))
        #country import 
        c_country_import[c in keys(import_countries_set),t in periods],
            sum(import_flow[n,t] for n in import_countries_set[c]) <= countries_supply[c]
        #export flow
        c_export_flow[node in setdiff(export_set, import_set), t in periods],
            sum(arc_flow[(src, node), t] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst),t] for dst in outneighbors(g, node)) + export_flow[node,t]
        #country export 
        c_country_export[c in keys(export_countries_set),t in periods],
            sum(export_flow[n,t] for n in export_countries_set[c]) == countries_demand[c]*demand_multiplier[t]
        #import + export for nodes that are both
        c_import_export_flow[node in intersect(export_set, import_set),t in periods],
            import_flow[node, t] + sum(arc_flow[(src, node),t] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst),t] for dst in outneighbors(g, node)) + export_flow[node,t]
        #assign FSRU to one port only
        c_fsru_assign[f in fsru_set,t in periods],
            sum(assign_fsru_to_port[port, f, t] for port in port_set) <= 1
        #max fsru per port
        c_port_assign[p in port_set,t in periods],
            sum(assign_fsru_to_port[p, f, t] for f in fsru_set) <= fsru_per_port[p]*port_upgraded[p,t]
        #arc capacities
        c_arc_capacity[a in arc_set,t in periods],
            arc_flow[a,t] <= arc_capacity[a]
        #bidirectional
        c_bidirectional[i in bidirectional_arc_set,t in periods],
            arc_flow[i,t] + arc_flow[(i[2], i[1]),t] <= arc_capacity[i]
        #upgrading
        c_upgrading[p in port_set, t in periods],
            port_upgraded[p,t] <= sum(port_upgrade[p,k] for k in 1:t)

        port_upgrade[port_dict["Wilhelmshaven"],1] == 1
        port_upgrade[port_dict["Brunsbüttel"],1] == 1
        port_upgrade[port_dict["Lubmin"],1] == 1
        port_upgrade[port_dict["Stade"],2] == 1
        port_upgrade[port_dict["Mukran"],2] == 1
    end
    @expression(model, capex_cost[t in periods], sum(port_upgrade[p,t]*port_capex[t] for p in port_set))
    @expression(model, opex_cost[t in periods], sum(assign_fsru_to_port[p,f,t]*port_opex for p in port_set, f in fsru_set))
    @expression(model, pipeline_construction_cost[t in periods], sum(port_upgrade[p,t]*fsru_per_port[p]*new_pipeline_length[p]*pipeline_cost_per_km for p in port_set))
    @expression(model, arc_flow_cost[t in periods], sum(arc_flow[a,t]*arc_length[a] for a in arc_set)*flow_cost)
    @expression(model, fsru_price_cost[t in periods], sum(fsru_flow[p,t] for p in port_set)*price_fsru)
    @expression(model, import_price_cost[t in periods], sum(country_price[c]*import_flow[n,t] for c in keys(import_countries_set) for n in import_countries_set[c]))
    @expression(model, total_cost, sum(γ^t*(capex_cost[t] + opex_cost[t] +  pipeline_construction_cost[t] + arc_flow_cost[t] + fsru_price_cost[t] + import_price_cost[t]) for t in periods))
    @objective model Min total_cost
end;
#optimize!(model) #Infeasible

p = 1e0
c_map = relax_with_penalty!(model, merge(Dict(model[:c_arc_capacity] .=> p), Dict(model[:c_bidirectional] .=> p)))

optimize!(model)
solution_summary(model)
penalties = Dict(con => value(penalty) for (con, penalty) in c_map if value(penalty) > 0);
@assert all(>=(0), values(penalties))
maximum(values(penalties))
pens = sum(values(penalties))

penalized_cons = filter(kv -> value(kv.second) > 0, c_map)
penalized_arcs = [eval(Meta.parse(match(r"\[(.*)\]", name(k)).captures[1]))[1] for k in keys(penalized_cons)] |> unique


println("\nPort upgrades:")
for (c,n) in port_dict 
    println(c*"($n)" => round.(Int,value.(port_upgrade)[n,:])')
end
println("\nimports:")
for (c, nodes) in import_countries_set
    println(c => [round(sum(value(import_flow[n,t]) for n in nodes), digits = 3) for t in periods]')
end
println("\nexports:")
for (c, nodes) in export_countries_set    
    println(c => [sum(value(export_flow[n,t]) for n in nodes) for t in periods]')
end
println("\nFSRU imports:")
for (c,n) in port_dict
    println(c*"($n)" => round.(value.(fsru_flow)[n,:], digits =2)')
end

println("capex: ", value(sum(capex_cost)) + value(sum(pipeline_construction_cost)))
println("opex: ", value(sum(opex_cost)))
fsruimp = value(sum(fsru_flow))
println("FSRU imports: ", fsruimp," ", fsruimp*price_fsru)
ttfimp = value(sum(sum(import_flow[n,:]) for n in import_set if n in reduce(vcat, [import_countries_set["BE"], import_countries_set["NL"], import_countries_set["FR"]])))
println("TTF imports: ", ttfimp," ", ttfimp*price_ttf)
hhimp = value(sum(sum(import_flow[n,:]) for n in import_set if n ∉ reduce(vcat, [import_countries_set["BE"], import_countries_set["NL"], import_countries_set["FR"]])))
println("HH imports: ", hhimp," ", hhimp*price_hh)
println("penalty: ", pens*p)
println("total cost (no penalties): ", value(total_cost) -  pens*p)