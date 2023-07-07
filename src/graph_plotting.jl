using GLMakie, GeoMakie, GeoJSON
export map_network
GLMakie.activate!(inline=false)

function map_network(g, consumers_dict, domestic_dict, port_nodes, import_dict, export_dict, port_coordinates; highlight_nodes = Int[], highlight_arcs = Tuple{Int,Int}[])
    #=countries = copy(GeoJSON.read(read("data/countries.geojson")))
    filter!(countries) do c
        c.ADMIN == "Germany"
    end

    polys = [copy(c.geometry.coordinates) for c in countries] #idxs: 1 = country, 2 = polys, 3 = points, 4 = coordinates =#

    #GeoJSON.write("data/DE_districts.geojson", GeoJSON.read(read(download("https://github.com/isellsoap/deutschlandGeoJSON/raw/main/3_regierungsbezirke/1_sehr_hoch.geo.json"))))
    polys = [c.geometry for c in copy(GeoJSON.read(read("data/DE_districts.geojson")))] 
    f = Figure();
    ax = GeoAxis(f[1,1];  lonlims = (5,20), latlims = (46,56));
    for poly in polys
        de = poly!(ax, GeoMakie.geo2basic(poly);strokewidth = 0.5, strokecolor = :black)
        de.inspectable[] = false
    end

    froms = Point2f[]
    tos_arrows = Point2f[]
    from_arrows = Point2f[]
    tos = Point2f[]
    edge_colors = Symbol[]
    for edge in edges(g)
        from_coo = props(g, vertices(g)[edge.src])[:coordinates]
        to_coo = props(g, vertices(g)[edge.dst])[:coordinates]
        push!(froms, Point2f(from_coo))
        arrowpoint = Point2f(to_coo) - Point2f(from_coo) .- 0.25f0.*(to_coo .- from_coo)
        push!(tos_arrows, arrowpoint)

        from_arrow_point = from_coo .+ arrowpoint
        push!(from_arrows, from_arrow_point)
        push!(tos, Point2f(to_coo) - from_arrow_point)
        push!(edge_colors, (edge.src, edge.dst) in highlight_arcs || (edge.dst, edge.src) in highlight_arcs ? :red : :black)
    end
    p1 = arrows!(ax, froms, tos_arrows, arrowcolor = edge_colors, color = edge_colors, linewidth = [c == :red ? 2 : 1 for c in edge_colors])
    p2 = arrows!(ax, from_arrows, tos, arrowcolor = edge_colors, arrowhead = ' ', color = edge_colors, linewidth = [c == :red ? 2 : 1 for c in edge_colors])
    p1.inspectable[] = p2.inspectable[] =  false
    
    port_points = [Point2f(get_prop(g, n, :coordinates)...) for (city, n) in port_nodes]
    p4 = scatter!(ax, port_points, markersize = 23, color = :green)
    p4.inspectable[] = false
    
    domestic_points = [Point2f(props(g, node)[:coordinates]...) for node in vertices(g) if node in values(domestic_dict)]
    domestic_labels = [prod(string(p.first,": ", p.second,"\n") for p in props(g, node)) for node in vertices(g) if node ∈ values(domestic_dict)]
    domestic_color = [node in highlight_nodes ? :red : :blue for node in vertices(g) if node ∈ values(domestic_dict)]
    scatter!(ax, domestic_points, inspector_label = (p,idx,pos) -> domestic_labels[idx], color = domestic_color, markersize = [c == :red ? 20 : 10 for c in domestic_color])

    consumer_points = [Point2f(props(g, node)[:coordinates]...) for node in vertices(g) if node ∈ values(consumers_dict)]
    consumer_labels = [prod(string(p.first,": ", p.second,"\n") for p in props(g, node)) for node in vertices(g) if node ∈ values(consumers_dict)]
    consumer_color = [node in highlight_nodes ? :red : :orange for node in vertices(g) if node ∈ values(consumers_dict)]
    p5 = scatter!(ax, consumer_points, inspector_label = (p, idx, pos) -> consumer_labels[idx],markersize = [c == :red ? 20 : 10 for c in consumer_color], color = consumer_color)

    import_points = [Point2f(props(g, node)[:coordinates]...) for node in vertices(g) if node ∈ values(import_dict)]
    import_labels = [prod(string(p.first,": ", p.second,"\n") for p in props(g, node)) for node in vertices(g) if node ∈ values(import_dict)]
    import_color = [node in highlight_nodes ? :red : :green for node in vertices(g) if node ∈ values(import_dict)]
    scatter!(ax, import_points, inspector_label = (p, idx, pos) -> import_labels[idx], markersize = [c == :red ? 20 : 10 for c in import_color], color = import_color, marker = :dtriangle)

    export_points = [Point2f(props(g, node)[:coordinates]...) for node in vertices(g) if node ∈ values(export_dict)]
    export_labels = [prod(string(p.first,": ", p.second,"\n") for p in props(g, node)) for node in vertices(g) if node ∈ values(export_dict)]
    export_color = [node in highlight_nodes ? :red : :orange for node in vertices(g) if node ∈ values(export_dict)]
    scatter!(ax, export_points, inspector_label = (p, idx, pos) -> export_labels[idx], markersize = [c == :red ? 20 : 10 for c in export_color], color = export_color, marker = :utriangle)


    city_points = [Point2f(p.second...) for p in port_coordinates]
    text!(ax, city_points, text = [p.first for p in port_coordinates])
    p3 = scatter!(ax, city_points, markersize = 18, marker = :diamond, color = :red, inspectable = false)
    #p3.inspector_label = (p, index, position) -> string(port_coordinates[index].first) * string("\nx: ", port_coordinates[index].second[1]) * string("\ny: ", port_coordinates[index].second[2])

    connection_points = [get_prop(g, port_nodes[p.first], :coordinates) .- p.second for p in port_coordinates]
    arrows!(ax, city_points, connection_points, arrowcolor = :black, arrowhead = ' ', linestyle = :dash, inspectable = false)

    DataInspector(f)
    display(f)
end
