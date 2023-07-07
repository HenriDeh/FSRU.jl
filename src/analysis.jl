using DataStructures
include("graph_construction.jl")
include("graph_plotting.jl")
FSRU.GLMakie.activate!(inline=false)

ports_coordinates = ["Wilhelmshaven" => (8.108275, 53.640799), "Brunsbutel" => (9.175174, 53.888166), "Lubmin" => (13.648727, 54.151454), "Stade" => (9.506341, 53.648904), "Emden" => (7.187397, 53.335209), "Rostock" => (12.106811, 54.098095), "Lubeck" => (10.685321, 53.874815), "Bremerhaven" => (8.526210, 53.593061), "Hambourg" => (9.962496, 53.507492), "Duisburg" => (6.739063, 51.431325)]

g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict  = create_graph(ports_coordinates)

map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_nodes = penalized_nodes)
map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs)

sp = floyd_warshall_shortest_paths(g)

begin
    unatainables = Int[]
    for i in demand_nodes_set
        if all(isinf, @view sp.dists[collect(supply_nodes_set),i])
            push!(unatainables, i)
        end
    end
    isempty(unatainables)
end

for u in unatainables
    for dst in outneighbors(g,u)
        if (dst => u) ∉ edges(g)
            add_edge!(g, dst, u, Dict(props(g, u, dst)..., :is_bidirectional => true))
            set_prop!(g, u, dst, :is_bidirectional, true)
        end
    end
end

sum(get_prop(g, v, :gdp_percentage) for v in vertices(g) if haskey(props(g,v), :gdp_percentage))


#sources = port_nodes
#destinations = values(consumers_dict)
#distances = Dict((s.second, d) => shortest_dists[s.second,d] for (s,d) in Iterators.product(sources,destinations))

#pipe_capacity(path) = minimum(props(g, path[i], path[i+1])[:capacity_Mm3_per_d] for i in eachindex(path)[1:end-1])=#