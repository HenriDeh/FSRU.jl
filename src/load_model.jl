using JuMP
import MultiObjectiveAlgorithms as MOA
begin
    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", 300.0)
    @variables model begin 
        port_upgrade[port_set,periods], Bin
        port_upgraded[port_set,periods], Bin
        assign_fsru_to_port[port_set,periods], Int
        0 <= arc_flow[i in arc_set, periods] 
        0 <= import_flow[import_set, periods]
        0 <= export_flow[export_set, periods]
        0 <= fsru_flow[port_set,periods]
        0 <= nodal_production[producers_set, periods]
        0 <= arc_overcapacity[arc_set, periods]
    end
    for node in node_set
        for t in periods
            rhs = zero(AffExpr) 
            lhs = zero(AffExpr)
            for src in inneighbors(g, node)
                add_to_expression!(lhs, arc_loss[(src, node)]*arc_flow[(src, node),t])
            end
            for dst in outneighbors(g, node)
                add_to_expression!(rhs, arc_flow[(node,dst),t])
            end
            if node in domestic_set || node in consumers_set
                add_to_expression!(rhs, nodal_demand[(node,t)])
            end
            if node in port_set 
                add_to_expression!(lhs, fsru_flow[node,t])
            end
            if node in import_set 
                add_to_expression!(lhs, import_flow[node,t])
            end
            if node in export_set
                add_to_expression!(rhs, export_flow[node,t])
            end
            if node in producers_set 
                add_to_expression!(lhs, nodal_production[node,t])
            end
            cons = @constraint(model, lhs == rhs)
        end
    end
    @constraints model begin
        #fsru port capacity
        c_fsru_port_capacity[p in port_set,t in periods],
            fsru_flow[p,t] <= assign_fsru_to_port[p, t]*fsru_cap[1]
        # #country import 
        c_country_import[c in keys(import_countries_set),t in periods],
            sum(import_flow[n,t] for n in import_countries_set[c]) <= countries_supply[c][t]
        #country export 
        c_country_export[c in keys(export_countries_set),t in periods],
            sum(export_flow[n,t] for n in export_countries_set[c]) == countries_demand[c]*demand_multiplier[t]
        # #assign FSRU to one port only
        # c_fsru_assign[f in fsru_set,t in periods],
        #     sum(assign_fsru_to_port[port, f, t] for port in port_set) <= 1
        #max fsru per port
        c_port_assign[p in port_set,t in periods],
            assign_fsru_to_port[p, t] <= fsru_per_port[p]*port_upgraded[p,t]
        #arc capacities
        c_arc_capacity[a in arc_set,t in periods],
            arc_flow[a,t] <= arc_capacity[a] + (a in inland_arc_set || !FSRU_USED || true ? arc_overcapacity[a,t] : 0.)
        # #bidirectional
        # c_bidirectional[i in bidirectional_arc_set,t in periods],
        #     arc_flow[i,t] + arc_flow[(i[2], i[1]),t] <= arc_capacity[i]
        #upgrading
        c_upgrading[p in port_set, t in periods],
            port_upgraded[p,t] == sum(port_upgrade[p,k] for k in 1:t)
        #domestic production
        c_production_capacity[node in producers_set, t in periods], 
            nodal_production[node, t] <= domestic_production_capacity[node]
    end
    if BROWNFIELD 
        @constraints model begin
            port_upgrade[port_dict["Wilhelmshaven"],1] == 1
            port_upgrade[port_dict["Brunsbüttel"],1] == 1
            port_upgrade[port_dict["Lubmin"],1] == 1
            port_upgrade[port_dict["Stade"],3] == 1
            port_upgrade[port_dict["Mukran"],2] == 1
        end
        for city in ["Emden" , "Rostock", "Lubeck", "Bremerhaven", "Hamburg", "Duisburg"]
            @constraint model sum(port_upgrade[port_dict[city],:]) == 0
        end
    end
    @expression(model, capex_cost[t in periods], r^(t-1)*sum(port_upgrade[p,t]*total_capex[p] for p in port_set))
    @expression(model, opex_cost[t in periods], r^(t-1)*sum(assign_fsru_to_port[p, t]*port_opex[p] for p in port_set))
    @expression(model, fsru_price_cost[t in periods], r^(t-1)*sum(fsru_flow[p,t] for p in port_set)*price_fsru)
    @expression(model, import_price_cost[t in periods], r^(t-1)*sum(country_price[c][t]*import_flow[n,t] for c in keys(import_countries_set) for n in import_countries_set[c]))
    @expression(model, domestic_price_cost[t in periods], r^(t-1)*sum(country_price["DE"][t]*nodal_production[n, t] for n in producers_set))
    @expression(model, total_cost, sum(capex_cost[t] + opex_cost[t] + fsru_price_cost[t] + import_price_cost[t] + domestic_price_cost[t] for t in periods))
    @expression(model, penalty, sum(arc_overcapacity[a,t]*arc_length[a] for a in arc_set for t in periods))
end;