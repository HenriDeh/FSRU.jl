using Distributions

function generate_toy_data(n_port::Int, n_DCs::Int)
    port_capacities = rand((1000,2000,3000), n_port)
    port_setup_cost = rand(100:1000, n_port)
    port_unit_capacity_cost = rand(Uniform(5,10), n_port)
    link_setup_cost = rand(100:100:2000, n_port, n_DCs)
    link_capacity_cost = rand(Uniform(0.5,1), n_port, n_DCs)
    link_max_capacity = rand(Poisson(3*n_port*2000/n_port/n_DCs), n_port, n_DCs)
    demand = min(sum(port_capacities), sum(link_max_capacity))/15
    #= Options for later
    budget
    =#
    return (link_max_capacity = link_max_capacity, port_capacities = port_capacities, port_setup_cost = port_setup_cost, port_unit_capacity_cost = port_unit_capacity_cost, link_capacity_cost = link_capacity_cost, demand = demand, link_setup_cost = link_setup_cost)
end


