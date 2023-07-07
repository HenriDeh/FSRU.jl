using JuMP, HiGHS #switch to gurobi later 

set_ports = ["Wilhelmshaven", "Brunsbutel", "Lubmin", "Stade", "Emden", "Rostock", "Lubeck", "Bremerhaven", "Hambourg", "Duisburg"]

function generate_short_term_parameters()
    #units are $m
    cost_pipeline_per_km(throughput) = 2.5 #tp in bcm

    #parameters
    ps = (;
        possible_throughput = [5,8,13,16] |> collect,
        cost_per_km = [tp*.3 for tp in [5,8,13,16] ],
        distance = [10,3,0.45,2,5,30,50,60,15,10],
        port_setup_cost = fill(96.7, 10),
        throughput_fsru = [5, 5, 4, 5, 5],
        ships_per_port = [2,1,1,1,1,1,1,1,1,1]
    )
    
    return ps
end

#check if feasible
#@assert sum(reverse(sort(throughput_fsru))[1:n_ships]) >= demand
function build_short_run_model(;distance::Vector, possible_throughput::Vector, cost_per_km::Vector, port_setup_cost::Vector, throughput_fsru::Vector, ships_per_port, set_ports, set_fsrus)
    n_port = length(port_setup_cost)
    n_ships = length(throughput_fsru)
    n_throughput = length(possible_throughput)
    #data check
    @assert length(distance) == n_port
    @assert length(cost_per_km) == n_throughput

    #Sets
    C = 1:n_throughput 
    I = 1:n_port
    F = 1:n_ships

    model = Model(HiGHS.Optimizer)

    @variables(model, begin 
        port_upgrade[I], Bin
        build_pipeline[I, C], Bin
        assign_fsru_to_port[I, F], Bin
    end)

    @objective(model, Min,  
        sum(port_upgrade[i]*port_setup_cost[i] for i in I) #port upgrading
        + sum(build_pipeline[i,c]*distance[i]*cost_per_km[c] for i in I, c in C) #pipeline building
    )

    @constraints(model, begin
        #A ship can only be assigned to an upgraded port & max # of ships per port
        c_port_assign[i in I],
            sum(assign_fsru_to_port[i, f] for f in F) <= port_upgrade[i]*ships_per_port[i]
        #A ship can be assigned to only one port. In this model, each ship must be assigned to a port.
        c_ship_assign[f in F],
            sum(assign_fsru_to_port[i, f] for i in I) == 1
        #A port must be equipped with pipelines with the same throughput as the ships
        c_throughput_pipelines[i in I],
            sum(assign_fsru_to_port[i, f]*throughput_fsru[f] for f in F) <= sum(build_pipeline[i,c]*possible_throughput[c] for c in C)
        #One pipeline per port
        c_one_pipeline_per_port[i in I],
            sum(build_pipeline[i,c] for c in C) <= 1

    end)
    return model
end


parameters = generate_short_term_parameters()
set_fsrus = string.(parameters.throughput_fsru) .* "bcm"

model = build_short_run_model(;parameters..., set_ports = set_ports, set_fsrus)
time = @elapsed optimize!(model)

PU = value.(model[:port_upgrade]) .|> round
BP = value.(model[:build_pipeline]) .|> round
FSRU = value.(model[:assign_fsru_to_port]) .|> round

upgraded_ports = [set_ports[idx] for (idx, i) in enumerate(PU) if i == 1]
built_pipelines = ["Port $(set_ports[idx[1]]) with throughput $(parameters.possible_throughput[idx[2]])" for idx in eachindex(BP) if BP[idx] == 1]
FSRU_assignments = ["FSRU $(set_fsrus[idx[2]]) to port $(set_ports[idx[1]])" for idx in eachindex(FSRU) if FSRU[idx] == 1]