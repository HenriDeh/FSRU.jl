using CSV, DataFrames, DataFramesMeta, GeoJSON, Graphs, MetaGraphs, Statistics, DataStructures
import Distances
export detect_islands, create_graph

function k_nearest_nodes(node, candidates, k) 
    candidates_s = sort(candidates, by = c-> Distances.euclidean(node, c))
    return candidates_s[1:k]
end

function detect_islands(g)
    paths = floyd_warshall_shortest_paths(g)
    unasigned = Set{Int}(collect(vertices(g)))
    subgraphs = Set{Int}[]
    for vertex in unasigned
        set = Set{Int}(vertex)
        pop!(unasigned, vertex)
        for (idx, dist) in enumerate(paths.dists[vertex, :])
            (dist == Inf || dist == 0) && continue
            push!(set, idx)
            pop!(unasigned, idx)
        end
        push!(subgraphs, set)
    end
    return subgraphs
end

##Loading and preprocessing
function create_graph(ports_coordinates)
    begin #load data
        nuts_fc = GeoJSON.read(read("data/NUTS_LB_2021_4326.geojson"))
        nuts_dict = Dict(f.NUTS_ID => f.geometry for f in nuts_fc)

        nodes_fc = GeoJSON.read(read("data/IGGIELGN_Nodes.geojson"))
        nodes_df = DataFrame(node_id = String[], x_coor = Float64[], y_coor = Float64[], country_code = String[], nuts_id_2 = String[])
        for n in nodes_fc
            n.country_code == "FI" && continue #remove nordstream
            push!(nodes_df, [n.id, n.geometry.coordinates..., n.country_code, n.param["nuts_id_2"]])
        end

        arcs_fc = GeoJSON.read(read("data/IGGIELGN_PipeSegments.geojson"))
        arcs_df = DataFrame(pipe_id = String[], from_x_coor = Float64[], from_y_coor = Float64[], to_x_coor = Float64[], to_y_coor = Float64[], from_node = String[], to_node = String[], from_country = String[], to_country = String[], diameter_mm = Float64[], length_km = Float64[], capacity_Mm3_per_d = Float64[], is_bothDirection = Int[])
        for a in arcs_fc
            #a.param.is_H_gas == 1 || continue #only H-Gas
            push!(arcs_df, (a.id, a.geometry[1][1], a.geometry[1][2], a.geometry[2][1], a.geometry[2][2], a.param["nuts_id_2"][1], a.param["nuts_id_2"][2], a.country_code[1], a.country_code[2],  a.param["diameter_mm"], a.param["length_km"], a.param["max_cap_M_m3_per_d"], a.param["is_bothDirection"]))
        end

        consumers_fc = GeoJSON.read(read("data/IGGIELGN_Consumers.geojson"))
        consumers_df = DataFrame(node_id = String[], x_coor = Float64[], y_coor = Float64[], country_code = String[], nuts_id_2 = String[], capacity_E_MW = Float64[], capacity_TH_MW= Float64[])
        for n in consumers_fc
            push!(consumers_df, [n.id, n.geometry.coordinates..., n.country_code, n.param["nuts_id_2"], n.param["capacity_E_MW"], n.param["capacity_TH_MW"]])
        end
        population_df = CSV.read("data/demo_r_pjangroup_linear.csv", DataFrame)
        @rsubset! population_df begin
            occursin(r"^DE..$", :geo) #filter DE nuts2
            :TIME_PERIOD == 2022
            :age == "TOTAL"
            :sex == "T"
        end
        @rselect! population_df begin 
            :geo 
            :population = :OBS_VALUE 
            :coordinates = get(nuts_dict, :geo) do 
                @error "$(:geo) not in dict"
            end
        end
        gdp_df = CSV.read("data/gdppc_nuts2.csv", DataFrame)
        @rselect! gdp_df begin
            :geo 
            :gdppc = :OBS_VALUE
        end
        @rsubset! gdp_df begin
            occursin(r"^DE..$", :geo) #filter DE nuts2
        end
        nuts_df = innerjoin(gdp_df, population_df, on = :geo)
        @rtransform! nuts_df begin
            :gdp = :gdppc * :population
        end
        TOTAL_GDP = sum(nuts_df.gdp)
    end
    @transform! nodes_df @byrow begin 
        :x_coor = round(:x_coor, digits = 6)
        :y_coor = round(:y_coor, digits = 6)
    end
    nodes_df_DE = filter(nodes_df) do n
        n.country_code == "DE"
    end
    @transform! consumers_df @byrow begin 
        :x_coor = round(:x_coor, digits = 6)
        :y_coor = round(:y_coor, digits = 6)
    end
    consumers_df_DE = filter(consumers_df) do n
        n.country_code == "DE"
    end
    arcs_df = @combine groupby(arcs_df, [:from_x_coor, :from_y_coor, :to_x_coor, :to_y_coor]) begin #merge duplicate arcs
        :pipe_id = prod(:pipe_id)
        :from_country = unique(:from_country)
        :to_country = unique(:to_country)
        :diameter_mm = maximum(:diameter_mm)
        :length_km = mean(:length_km)
        :capacity_Mm3_per_d = sum(:capacity_Mm3_per_d)
        :is_bothDirection = maximum(:is_bothDirection)
    end

    @transform! arcs_df @byrow begin
        :from_x_coor = round(:from_x_coor, digits = 6) 
        :from_y_coor = round(:from_y_coor, digits = 6) 
        :to_x_coor = round(:to_x_coor, digits = 6) 
        :to_y_coor= round(:to_y_coor, digits = 6) 
    end

    @rsubset! arcs_df begin #remove arcs that connect a node to itself
        (:from_x_coor, :from_y_coor) != (:to_x_coor, :to_y_coor)
    end

    #instantiate empty graph
    g = MetaDiGraph(SimpleDiGraph(), Inf)
    defaultweight!(g, 0.)
    weightfield!(g, :length_km)
    ##### Islands removal
    g_i = MetaGraph(g)
    coo_to_node = Dict{Tuple{Float64,Float64}, Int}()
    
    for (id,r) in enumerate(eachrow(nodes_df_DE))
        @assert add_vertex!(g_i)
        if (r.x_coor, r.y_coor) in keys(coo_to_node)
            @warn "Duplicate nodes at identical coordinates"
        end
        push!(coo_to_node, (r.x_coor, r.y_coor) => id)
    end
    for r in eachrow(arcs_df)
        if r.to_country != "DE" || r.from_country != "DE"
            continue
        end
        from, to = coo_to_node[(r.from_x_coor, r.from_y_coor)], coo_to_node[(r.to_x_coor, r.to_y_coor)]
        inserted = add_edge!(g_i, from, to, Dict(:length_km => r.length_km))
    end
    islands = sort(detect_islands(g_i), by = length)[1:end-1]
    rem_nodes = collect(reduce(union,islands))
    if !isempty(islands)
        @info "$(length(islands)) islands of $(length(rem_nodes)) disconnected nodes were removed. They respectively contained $(length.(islands)) nodes."
        removed_nodes = nodes_df_DE[rem_nodes,:]
        deleteat!(nodes_df_DE, sort(rem_nodes))
    end
    empty!(coo_to_node)
    ############### Nodes addition

    for (id,r) in enumerate(eachrow(nodes_df_DE))
        @assert add_vertex!(g, Dict(:node_number => id, :node_id => r.node_id, :coordinates => (r.x_coor, r.y_coor), :country => r.country_code, :nuts2 => r.nuts_id_2))
        if (r.x_coor, r.y_coor) in keys(coo_to_node)
            @warn "Duplicate nodes at identical coordinates"
        end
        push!(coo_to_node, (r.x_coor, r.y_coor) => id)
    end
    unlinked_nuts = filter(n -> n ∉ nodes_df_DE.nuts_id_2, population_df.geo) 
    all(n -> n in population_df.geo, nodes_df_DE.nuts_id_2)

    ##############Edges addition
    for r in eachrow(arcs_df)
        if r.to_country != "DE" || r.from_country != "DE" || (r.from_x_coor, r.from_y_coor) ∉ keys(coo_to_node) || (r.to_x_coor, r.to_y_coor) ∉ keys(coo_to_node)
            continue
        end
        from, to = coo_to_node[(r.from_x_coor, r.from_y_coor)], coo_to_node[(r.to_x_coor, r.to_y_coor)]
        inserted = add_edge!(g, from, to, Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d,:is_bidirectional => r.is_bothDirection))
        if !inserted
            @error "arc $r not inserted"
        end
        if r.is_bothDirection == 1
            inserted2 = add_edge!(g, to, from, Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d, :is_bidirectional => r.is_bothDirection))
            if !inserted2
                @error "arc $r not inserted in reverse"
            end
        end
    end

    ######### Consumer node props
    consumers_dict = Dict{Tuple{Float64,Float64}, Int}()
    for r in eachrow(consumers_df_DE)
        coo = (r.x_coor, r.y_coor)
        coo in keys(coo_to_node) || continue
        node_id = coo_to_node[coo]
        set_props!(g, node_id, Dict(:capacity_E_MW => r.capacity_E_MW, :capacity_TH_MW => r.capacity_TH_MW))
        push!(consumers_dict, coo => node_id)
    end
    total_E_MW = sum(props(g, node)[:capacity_E_MW] for node in values(consumers_dict) if props(g, node)[:country] == "DE")
    total_TH_MW = sum(props(g, node)[:capacity_TH_MW] for node in values(consumers_dict) if props(g, node)[:country] == "DE")
    total_MW = total_E_MW + total_TH_MW
    for node in values(consumers_dict) 
        props(g, node)[:country] == "DE" || continue
        percentage_capacity = (props(g, node)[:capacity_E_MW] + props(g, node)[:capacity_TH_MW])/total_MW
        set_prop!(g, node, :demand_percentage, percentage_capacity)
    end


    
    ######### Ports linkages
    port_nodes = Dict{String, Int}()
    candidates = collect(k for (k,v) in coo_to_node if outdegree(g, v) >= 1)
    for (port_name,coor) in ports_coordinates
        closest = k_nearest_nodes(coor, candidates , 1)
        closest_node = coo_to_node[only(closest)]
        push!(port_nodes, port_name=> closest_node)
    end

    ###### Import/Export
    border_arcs = filter(arcs_df) do r
        ((r.to_country != "DE") ⊻ (r.from_country != "DE"))
    end

    import_nodes = Dict{Tuple{Float64,Float64}, Int}()
    export_nodes = Dict{Tuple{Float64,Float64}, Int}()
    
    incoming_arcs = @rsubset border_arcs begin 
        :to_country == "DE"
        (:to_x_coor, :to_y_coor) in keys(coo_to_node)
    end
    outgoing_arcs = @rsubset border_arcs begin 
        :from_country == "DE"
        (:from_x_coor, :from_y_coor) in keys(coo_to_node)
    end
    for r in eachrow(incoming_arcs)
        if r.from_country == "XX"
            r.from_country = "NO"
        end
    end
    @show keys(groupby(incoming_arcs, :from_country))
    for country_group in groupby(outgoing_arcs, :to_country)
        for group in groupby(country_group, [:to_x_coor, :to_y_coor])
            to_coordinates = (first(group).to_x_coor, first(group).to_y_coor)
            add_vertex!(g, Dict(:node_number => nv(g)+1, :coordinates => to_coordinates, :country => first(group).to_country , :is_export => true))
            push!(export_nodes, to_coordinates => nv(g))
            push!(coo_to_node, to_coordinates => nv(g))
            for r in eachrow(group)
                from_coordinates = (r.from_x_coor, r.from_y_coor)
                from_node = coo_to_node[from_coordinates]
                add_edge!(g, from_node, coo_to_node[to_coordinates], Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d, :is_bidirectional => r.is_bothDirection))
                if r.is_bothDirection == 1 || first(group).to_country == "BE"
                    add_edge!(g, coo_to_node[to_coordinates],from_node, Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d, :is_bidirectional => r.is_bothDirection))
                    set_props!(g, coo_to_node[to_coordinates], Dict(:is_import => true))
                    push!(import_nodes, to_coordinates => coo_to_node[to_coordinates])
                end
            end
        end
    end
    for country_group in groupby(incoming_arcs, :from_country)
        for group in groupby(country_group, [:from_x_coor, :from_y_coor])
            from_coordinates = (first(group).from_x_coor, first(group).from_y_coor)
            if from_coordinates ∉ keys(export_nodes)
                add_vertex!(g, Dict(:node_number => nv(g)+1, :coordinates => from_coordinates, :country => first(group).from_country , :is_import => true))
                push!(coo_to_node, from_coordinates => nv(g))
            else
                set_props!(g, coo_to_node[from_coordinates], Dict(:is_import => true))
            end
            push!(import_nodes, from_coordinates => coo_to_node[from_coordinates])
            for r in eachrow(group)
                to_coordinates = (r.to_x_coor, r.to_y_coor)
                to_node = coo_to_node[to_coordinates]
                add_edge!(g, coo_to_node[from_coordinates], to_node, Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d, :is_bidirectional => r.is_bothDirection))
                if r.is_bothDirection == 1
                    add_edge!(g, to_node, coo_to_node[from_coordinates], Dict(:diameter_mm => r.diameter_mm, :length_km => r.length_km, :capacity_Mm3_per_d => r.capacity_Mm3_per_d, :is_bidirectional => r.is_bothDirection))
                    set_props!(g, coo_to_node[from_coordinates], Dict(:is_export => true))
                    push!(export_nodes, from_coordinates => coo_to_node[from_coordinates])
                end
            end
        end
    end
    sp = floyd_warshall_shortest_paths(g)
    
    domestic_df = @chain nodes_df_DE begin
        @rsubset (:x_coor, :y_coor) ∉ keys(consumers_dict) && (:x_coor, :y_coor) in keys(coo_to_node)
    end
    domestic_dict = Dict{Tuple{Float64,Float64}, Int}()
    for r in eachrow(domestic_df)
        coo = (r.x_coor, r.y_coor)
        node_id = coo_to_node[coo]
        push!(domestic_dict, coo => node_id)
    end 

    unatainables = Set{Int}()
    for i in union(Set(values(domestic_dict)), Set(values(consumers_dict)))
        for node in values(import_nodes)
            if indegree(g,i) == 0 || all(isinf, @view sp.dists[collect(setdiff(values(import_nodes), node)),i]) 
                push!(unatainables, i)
            end
        end
    end
    artificial_arcs = 0
    for u in unatainables 
        for dst in outneighbors(g,u)
            if (dst => u) ∉ edges(g)
                artificial_arcs += 1
                add_edge!(g, dst, u, Dict(props(g, u, dst)..., :is_bidirectional => true))
                set_prop!(g, u, dst, :is_bidirectional, true)
                if get_prop(g, dst, :country) != "DE"
                    set_prop!(g, dst, :is_import, true)
                    push!(import_nodes, get_prop(g, dst, :coordinates) => dst)
                end
            end
        end
    end
    if !isempty(unatainables)
        @info "$(length(unatainables)) nodes were not atainables by at least two import node. $artificial_arcs outgoing artificial arcs were added."
    end

    ############# Domestic nodes demands
    domestic_df = innerjoin(domestic_df, nuts_df, on = :nuts_id_2 => :geo)
    @rename! domestic_df begin :nuts_2_coordinates = :coordinates; :nuts_gdp = :gdp end
    nuts_incapacities = Dict{String, Float64}()
    for r in eachrow(domestic_df)
        coo = (r.x_coor, r.y_coor)
        node_id = coo_to_node[coo]
        incapacity = sum(get_prop(g, n, node_id, :capacity_Mm3_per_d) for n in inneighbors(g, node_id))
        setindex!(nuts_incapacities, get!(nuts_incapacities, r.nuts_id_2, 0.) + incapacity, r.nuts_id_2)
        push!(domestic_dict, coo => node_id)
    end
    for r in eachrow(domestic_df)        
        coo = (r.x_coor, r.y_coor)
        node_id = coo_to_node[coo]
        incapacity = sum(get_prop(g, n, node_id, :capacity_Mm3_per_d) for n in inneighbors(g, node_id))
        node_nut_proportion = incapacity / nuts_incapacities[r.nuts_id_2]
        nut_proportion = r.nuts_gdp / TOTAL_GDP
        set_props!(g, node_id, Dict(:gdp_percentage => nut_proportion*node_nut_proportion))
    end
    
    ######## Unrepresented nuts
    if !isempty(unlinked_nuts) 
        @info "The following nuts2 had no nodes and had their demand assigned to nearest neighbours: $(unlinked_nuts)"
    end
    for nut in unlinked_nuts
        nut_row = only(@rsubset nuts_df :geo == nut)
        coor = tuple(nut_row.coordinates.coordinates...)
        nut_proportion = nut_row.gdp/TOTAL_GDP
        k_neighbours = round(Int,nut_proportion*nv(g))
        knn = k_nearest_nodes(coor, collect(keys(domestic_dict)), k_neighbours)
        total_neigh_incapacity = sum(get_prop(g, inneigh, coo_to_node[neigh], :capacity_Mm3_per_d) for neigh in knn for inneigh in inneighbors(g, coo_to_node[neigh]))
        for neigh in knn
            node_id = coo_to_node[neigh]
            incapacity = sum(get_prop(g, n, node_id, :capacity_Mm3_per_d) for n in inneighbors(g, node_id))
            current_percentage = get_prop(g, node_id, :gdp_percentage)
            set_prop!(g, node_id, :gdp_percentage, current_percentage + incapacity/total_neigh_incapacity*nut_proportion) #add the unlinked percentage to old percentage
        end
    end
    return g, consumers_dict, domestic_dict, port_nodes, import_nodes, export_nodes
end
