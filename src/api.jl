export generate_map_greenfield, generate_map_brownfield

function generate_map_greenfield()
    include("src/model_greenfield.jl")
    FSRU.GLMakie.activate!(inline=false)
    display(map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs))
end
function generate_map_brownfield()
    include("src/model_brownfield.jl")
    FSRU.GLMakie.activate!(inline=false)
    display(map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs))
end