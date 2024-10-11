using Distances, StatsBase
ports_coordinates = Dict(["Mukran" => (13.644526, 54.512157),"Wilhelmshaven" => (8.108275, 53.640799), "Brunsbüttel" => (9.175174, 53.888166), "Lubmin" => (13.648727, 54.151454), "Stade" => (9.506341, 53.648904), "Emden" => (7.187397, 53.335209), "Rostock" => (12.106811, 54.098095), "Lubeck" => (10.685321, 53.874815), "Bremerhaven" => (8.526210, 53.593061), "Hamburg" => (9.962496, 53.507492), "Duisburg" => (6.739063, 51.431325)])

g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, producers_dict  = create_graph(ports_coordinates, silent = SILENT)

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
    producers_set = values(producers_dict)
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
    foreign_nodes_set = union(export_set, import_set)
    inland_arc_set = Set((src,dst) for (src,dst) in arc_set if src ∉ foreign_nodes_set && dst ∉ foreign_nodes_set)
end;