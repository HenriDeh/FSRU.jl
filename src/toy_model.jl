using JuMP, HiGHS #switch to gurobi later 

include("toy_data.jl")

function build_toy_model(n_port::Int, n_DCs::Int)
    data = generate_toy_data(n_port, n_DCs)
    model = Model(HiGHS.Optimizer)

    @variables(model, begin 
        port_upgrade[1:n_port], Bin
        port_capacity[i = 1:n_port] >= 0
        build_pipeline[1:n_port, 1:n_DCs], Bin
        pipeline_capacity[1:n_port, 1:n_DCs] >= 0
    end)

    @objective(model, Min,  sum(port_upgrade[i]*data.port_setup_cost[i] + port_capacity[i]* data.port_unit_capacity_cost[i] for i in 1:n_port) 
                            + sum(build_pipeline[i,j]*data.link_setup_cost[i,j] + pipeline_capacity[i,j]* data.link_capacity_cost[i,j] for i in 1:n_port, j in 1:n_DCs) 
    )

    @constraints(model, begin
        #The inflow capacity of a port cannot exceed a given maximum
        c_port_max_capacity[i = 1:n_port], 
            port_upgrade[i]*data.port_capacities[i] >= port_capacity[i]
        #The flow capacity of a pipeline cannot exceed a given maximum
        c_pipeline_max_capacity[i = 1:n_port, j = 1:n_DCs], 
            data.link_max_capacity[i,j]*build_pipeline[i, j] >= pipeline_capacity[i,j]
        #All the inflow capacity of a port must come with an equivalent outflow pipeline capacity
        c_flow_at_port[i = 1:n_port],   
            port_capacity[i] == sum(pipeline_capacity[i,j] for j in 1:n_DCs)
        #The demand must be satified
        demand_satisfaction[j = 1:n_DCs],
            sum(pipeline_capacity[i,j] for i in 1:n_port) == data.demand
    end)
    return model
end

model = build_toy_model(10,5)
time = @elapsed optimize!(model)
solution_summary(model)
value.(model[:port_upgrade]) .|> round
value.(model[:build_pipeline]) .|> round
value.(model[:port_capacity]) .|> round
value.(model[:pipeline_capacity]) .|> round


