export generate_map

function generate_map()
    include("src/model_greenfield.jl")
    FSRU.GLMakie.activate!(inline=false)
    display(map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs))
end