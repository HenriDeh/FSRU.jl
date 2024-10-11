using JuMP, Format

# p = 1e5
# c_map = relax_with_penalty!(model, merge(Dict(model[:c_arc_capacity][(i,j), t] .=> p for (i,j) in arc_set for t in periods if !FSRU_USED || all(in(demand_nodes_set), (i,j)))))#, Dict(model[:c_bidirectional][(i,j), t] .=> p for (i,j) in bidirectional_arc_set for t in periods if !FSRU_USED || all(in(demand_nodes_set), (i,j)))))
@objective model Min penalty*0.455 + total_cost
optimize!(model)
# min_pen = objective_value(model)
# @constraint model penalty <= min_pen*1.2
# @objective model Min total_cost
# optimize!(model)

gaps[scenario_name] = relative_gap(model)
#solution_summary(model)
# penalties = Dict(con => value(penalty) for (con, penalty) in c_map if value(penalty) > 0);
# @assert all(>=(0), values(penalties))
# maximum(values(penalties))
# pens = sum(values(penalties))

# penalized_cons = filter(kv -> value(kv.second) > 0, c_map)
# penalized_arcs = [eval(Meta.parse(match(r"\[(.*)\]", name(k)).captures[1]))[1] for k in keys(penalized_cons)] |> unique
penalized_arcs = [a for a in arc_set if any(>(0), value.(arc_overcapacity[a,:]))]


if !SILENT
    println("\nPort upgrades:")
    for (c,n) in port_dict 
        println(c*"($n)" => round.(Int,value.(port_upgrade)[n,:])')
    end
    println("\nimports:")
    for (c, nodes) in import_countries_set
        println(c => [round(sum(value(import_flow[n,t]) for n in nodes), digits = 3) for t in periods]')
    end
    println("\nexports:")
    for (c, nodes) in export_countries_set    
        println(c => [round(sum(value(export_flow[n,t]) for n in nodes), digits = 2) for t in periods]')
    end
    println("\nFSRU imports:")
    for (c,n) in port_dict
        println(c*"($n)" => round.(value.(fsru_flow)[n,:], digits =2)')
    end
    println("\ndomestic production:")
    for (c,n) in producers_dict
        println(n," => ", round.(value.(nodal_production[n,:]),digits=2)')
    end
    value.(nodal_production)

    format_lat(x) = format(Int(round(value(x))), commas = true)
    cap = format_lat(sum(capex_cost))
    op = format_lat(sum(opex_cost))
    println("capex: ", cap)
    println("opex: ", op)

    fsruimp = format_lat(sum(fsru_price_cost/price_fsru))
    fsrucost = format_lat(sum(fsru_price_cost))
    println("FSRU imports: ", fsruimp," ", fsrucost)

    ttfexp = sum(sum(import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("BE","NL","FR","CH")) for t in periods)
    ttfimp = format_lat(ttfexp)
    ttfcostexp = sum(r^t*sum(country_price[c][t]*import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("BE","NL","FR","CH")) for t in periods)
    ttfcost = format_lat(ttfcostexp)
    println("TTF imports: ", ttfimp," ", ttfcost)

    hhexp = sum(sum(import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("NO","DK")) for t in periods)
    hhimp = format_lat(hhexp)
    hhcostexp = sum(r^t*sum(country_price[c][t]*import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("NO","DK")) for t in periods)
    hhcost = format_lat(hhcostexp)
    println("HH imports: ", hhimp," ", hhcost)

    transitexp = sum(sum(import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("AT","CZ","FI","PL")) for t in periods)
    transitimp = format_lat(transitexp)
    transitcostexp = sum(r^t*sum(country_price[c][t]*import_flow[n,t] for (c, nodes) in import_countries_set for n in nodes if c in ("AT","CZ","FI","PL")) for t in periods)
    transitcost = format_lat(transitcostexp)
    println("Transit imports: ", transitimp," ", transitcost)

    domexp = sum(sum(nodal_production[n, t] for n in producers_set) for t in periods)
    domcostexp = sum(domestic_price_cost)
    domprod = format_lat(domexp)
    domprodcost = format_lat(domcostexp)

    tot =  format_lat(total_cost)
    total_bcm = hhexp + ttfexp + sum(fsru_flow) + domexp + transitexp
    # ps = format_lat(pens*p)
    # ps_bcm = format_lat(pens)
    # println("penalty: ", ps, " ", ps_bcm)
    println("total cost (no penalties): ", tot)

    total_bcm_f = format_lat(total_bcm)
    cap_bcm = format_lat(sum(capex_cost) / total_bcm)
    opex_bcm = format_lat(sum(opex_cost) / total_bcm)
end
