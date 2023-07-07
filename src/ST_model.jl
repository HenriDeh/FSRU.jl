using FSRU, Distances, JuMP

ports_coordinates = Dict(["Wilhelmshaven" => (8.108275, 53.640799), "Brunsbutel" => (9.175174, 53.888166), "Lubmin" => (13.648727, 54.151454), "Stade" => (9.506341, 53.648904), "Emden" => (7.187397, 53.335209), "Rostock" => (12.106811, 54.098095), "Lubeck" => (10.685321, 53.874815), "Bremerhaven" => (8.526210, 53.593061), "Hambourg" => (9.962496, 53.507492), "Duisburg" => (6.739063, 51.431325)])

g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict  = create_graph(ports_coordinates)

##Sets 
begin
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
    fsru_set = 1:5
    demand_nodes_set = union(Set(domestic_set), Set(consumers_set))
    supply_nodes_set = union(Set(port_set), Set(import_set))
end
##Parameters 
begin
    arc_capacity = Dict([a => get_prop(g, a..., :capacity_Mm3_per_d)*365/1000 for a in arc_set]) #bcm3 per year
    arc_bidirectional = Dict([a => get_prop(g, a..., :is_bidirectional) for a in arc_set])
    arc_length = Dict(a => get_prop(g, a..., :length_km) for a in arc_set)
    flow_cost = 1 #M€/km/bcm3
    ##Supply
    #import    
    countries_supply = Dict("BE" => 26.58, "AT" => 0.39, "NO" => 49.24, "CZ" => 11.96, "CH" => 1.69, "FR" => 0.42, "PL" => 0.3, "DK" => 0.001, "NL" => 26.15, "FI" => 0.) #bcm3 per year
    total_import = sum(values(countries_supply))
    #ports
    fsru_per_port = Dict(port_set .=> 1); 
    fsru_per_port[port_dict["Wilhelmshaven"]] = 2
    new_pipeline_length = Dict(node => haversine(ports_coordinates[city], get_prop(g,node,:coordinates))/1000 for (city, node) in port_dict) #km
    port_setup_cost = 96.7  #M€ 
    pipeline_cost_per_km = 0.3 #M€
    #FSRUs
    fsru_cap = Dict(fsru_set .=> 5) #bcm3 per year                                                                                          
    #all
    total_supply = sum(values(countries_supply)) + sum(values(fsru_cap))
    ##Demand
    #export
    countries_demand = Dict("BE" => 0., "AT" => 8.03, "LU" => 0., "CZ" => 29.57, "CH" => 3.36, "FR" => 1.37, "PL" => 3.76, "FI" => 0., "DK" => 2.17, "NL" => 2.77) #bcm3 per year 
    total_export = sum(values(countries_demand))                                                  
    #domestic
    total_domestic_demand = 0.59*(total_supply - total_export) #bcm3 per year
    PERCENTAGE_SATISFIED = sum(get_prop(g, n, :gdp_percentage) for n in domestic_set)
    nodal_domestic_demand = Dict(n => get_prop(g, n, :gdp_percentage)*total_domestic_demand*1/PERCENTAGE_SATISFIED for n in domestic_set)
    #industrial
    total_industrial_demand = 0.41*(total_supply - total_export) #bcm3 per year
    nodal_industrial_demand = Dict(n => get_prop(g, n, :demand_percentage)*total_industrial_demand for n in consumers_set)
    #all demand 
    nodal_demand = merge(nodal_domestic_demand, nodal_industrial_demand)
    NET_IMPORT = sum(values(countries_supply)) - sum(values(countries_demand))
end
##Model
begin
    model = Model(HiGHS.Optimizer)
    @variables model begin 
        port_upgrade[port_set], Bin
        assign_fsru_to_port[port_set, fsru_set], Bin
        0 <= arc_flow[i in arc_set] 
        0 <= import_flow[import_set]
        0 <= export_flow[export_set]
        0 <= fsru_flow[port_set]
    end
    @constraints model begin
        #demand satisfaction and flow conservation o
        c_demand_flow[node in setdiff(demand_nodes_set, port_set)],
            sum(arc_flow[(src, node)] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst)] for dst in outneighbors(g, node)) + nodal_demand[node]
        #demand satisfaction and flow conservation at ports o
        c_demand_flow_port[node in port_set],
                fsru_flow[node] + sum(arc_flow[(src, node)] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst)] for dst in outneighbors(g, node)) + nodal_demand[node] 
        #fsru port capacity o
        c_fsru_port_capacity[p in port_set],
            fsru_flow[p] <= sum(assign_fsru_to_port[p, f]*fsru_cap[f] for f in fsru_set)
        #import flow o
        c_import_flow[node in setdiff(import_set,export_set)],
            import_flow[node] + sum(arc_flow[(src, node)] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst)] for dst in outneighbors(g, node))
        #country import 
        c_country_import[c in keys(import_countries_set)],
            sum(import_flow[n] for n in import_countries_set[c]) <= countries_supply[c]
        #export flow o
        c_export_flow[node in setdiff(export_set, import_set)],
            sum(arc_flow[(src, node)] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst)] for dst in outneighbors(g, node)) + export_flow[node]
        #country export 
        c_country_export[c in keys(export_countries_set)],
            sum(export_flow[n] for n in export_countries_set[c]) == countries_demand[c]
        #import + export for nodes that are both o
        c_import_export_flow[node in intersect(export_set, import_set)],
            import_flow[node] + sum(arc_flow[(src, node)] for src in inneighbors(g, node)) == sum(arc_flow[(node,dst)] for dst in outneighbors(g, node)) + export_flow[node]
        #assign each FSRU to a porto
        c_fsru_assign[f in fsru_set],
            sum(assign_fsru_to_port[port, f] for port in port_set) == 1
        #max fsru per porto
        c_port_assign[p in port_set],
            sum(assign_fsru_to_port[p, f] for f in fsru_set) <= fsru_per_port[p]*port_upgrade[p]
        #arc capacitieso
        c_arc_capacity[a in arc_set],
            arc_flow[a] <= arc_capacity[a]
        #bidirectionalo
        c_bidirectional[i in bidirectional_arc_set],
            arc_flow[i] + arc_flow[(i[2], i[1])] <= arc_capacity[i]
    end
    @objective model Min sum(port_upgrade[p]*port_setup_cost for p in port_set) +
                        sum(sum(assign_fsru_to_port[p, f] for f in fsru_set)*new_pipeline_length[p]*pipeline_cost_per_km for p in port_set) +
                        sum(arc_flow[a]*arc_length[a] for a in arc_set)*flow_cost
end
optimize!(model)
solution_summary(model)

#c_map = relax_with_penalty!(model, default = 10000000)
p = 1e4
#c_map = relax_with_penalty!(model, merge(Dict(model[:c_demand_flow] .=> p), Dict(model[:c_demand_flow_port] .=> p), Dict(model[:c_import_flow] .=> p), Dict(model[:c_export_flow] .=> p), Dict(model[:c_import_export_flow] .=> p)))
c_map = relax_with_penalty!(model, merge(Dict(model[:c_arc_capacity] .=> p), Dict(model[:c_bidirectional] .=> p)))
optimize!(model)
solution_summary(model)
penalties = Dict(con => value(penalty) for (con, penalty) in c_map if value(penalty) > 0);
sum(values(penalties))

penalized_cons = filter(kv -> value(kv.second) > 0, c_map)
#penalized_nodes = [parse(Int,match(r"(\d+)", name(k)).captures[1]) for k in keys(penalized_cons)]
penalized_arcs = [eval(Meta.parse(match(r"\[(.*)\]", name(k)).captures[1])) for k in keys(penalized_cons)]


println("Port upgrades:")
[c*"($n)" => round(Int,value.(port_upgrade)[n]) for (c,n) in port_dict]
println("FSRU per port:")
[c*"($n)" => round(Int, sum(value.(assign_fsru_to_port)[n,:])) for (c,n) in port_dict]
println("imports:")
[c => sum(value(import_flow[n]) for n in nodes) for (c, nodes) in import_countries_set]
println("exports:")
[c => sum(value(export_flow[n]) for n in nodes) for (c, nodes) in export_countries_set]
