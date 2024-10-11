##Parameters 
begin
    r = 1-0.01715
    demand_multiplier = range(start = 1, stop = 0, length = length(periods)+1)[2:end]
    arc_capacity = Dict([a => get_prop(g, a..., :capacity_Mm3_per_d)*365/1000 for a in arc_set]) #bcm3 per year
    arc_bidirectional = Dict([a => get_prop(g, a..., :is_bidirectional) for a in arc_set])
    arc_length = Dict(a => get_prop(g, a..., :length_km) for a in arc_set)
    # arc_loss = Dict(a => 1 for a in arc_set)
    arc_loss = Dict(a => a in inland_arc_set ? 1 - arc_length[a]*0.00005 - 0.000425347 : 1. for a in arc_set)
    ##Supply
    #import    
    countries_supply = Dict("BE" => fill(26.58, last(periods)), 
                            "AT" => fill(0.39, last(periods)), 
                            "NO" => fill(49.24, last(periods)), 
                            "CZ" => fill(11.96, last(periods)), 
                            "CH" => fill(1.69, last(periods)), 
                            "FR" => fill(0.42, last(periods)), 
                            "PL" => fill(0.3, last(periods)), 
                            "DK" => fill(0.001, last(periods)), 
                            "NL" => fill(26.15, last(periods)), 
                            "FI" => fill(0., last(periods))
                        ) #bcm3 per year
    if RUSSIA
        countries_supply["AT"][5:end] .= 200
        countries_supply["PL"][5:end] .= 200
        countries_supply["CZ"][5:end] .= 200
        countries_supply["FI"][5:end] .= 200         
    end
    if !FSRU_USED 
        russia_gas = 1697.85/9769.44*365 #GWh/d to bcm/y
        totlngsupply = sum(countries_supply[c][1] for c in ["BE", "FR", "NL", "CH"])
        sharerussia = Dict(c => countries_supply[c][1]/totlngsupply for c in ["BE", "FR", "NL", "CH"])
        for c in ["BE", "FR", "NL", "CH"]
            countries_supply[c] .+= sharerussia[c]*russia_gas
        end
    end
    price_fsru = 31.087*9769444.44/1e6 # ACER EU spot price [EUR/MWh] converted to M€/bcm (avg 01 -> 07 2024)
    price_ttf = 33.339*9769444.44/1e6 # add ACER TTF benchmark, converted (avg 01 -> 07 2024)
    price_hh = 90.27687803 # $/mmbtu converted to M€/bcm (US EIA) (avg 01->09 2024)
    price_at = 397.05 #E-control
    country_price = Dict(
                        "DE" => fill(price_hh, last(periods)),
                        "BE" => fill(price_ttf, last(periods)),
                        "AT" => fill(price_at, last(periods)), #Mwh->bcm * Gas Connect Austria price/Mwh [M€/bcm]
                        "NO" => fill(price_hh, last(periods)),
                        "CZ" => fill(price_at, last(periods)),
                        "CH" => fill(price_ttf, last(periods)),#Transit from Italian regasified LNG
                        "FR" => fill(price_ttf, last(periods)),
                        "PL" => fill(price_at, last(periods)),
                        "DK" => fill(price_hh, last(periods)),
                        "NL" => fill(price_ttf, last(periods)),
                        "FI" => fill(price_hh, last(periods)))   
    if RUSSIA
        country_price["AT"][5:end] .= price_hh
        country_price["PL"][5:end] .= price_hh
        country_price["CZ"][5:end] .= price_hh
        country_price["FI"][5:end] .= price_hh
    end
    total_import = sum(values(countries_supply))
    #ports
    if FSRU_USED
        fsru_per_port = Dict(port_set .=> 1); 
        fsru_per_port[port_dict["Wilhelmshaven"]] = 2
    else
        fsru_per_port = Dict(port_set .=> 0); 
    end
    new_pipeline_length = Dict(node => haversine(ports_coordinates[city], get_prop(g,node,:coordinates))/1000 for (city, node) in port_dict) #km
    investment_horizon = 10
    pipeline_cost_per_km = 0.3  #(capex + opex, depends on diameter) #M€
    lease_cost = 46 #0.130*1.228*365 # 
    #infra_capex = Dict(p => fsru_per_port[p]*infra_capex for p in port_set)
    infra_capex = Dict(p => 1.228*((fsru_per_port[p]*80+30)*1.1+54) for p in port_set)
    pipeline_capex = Dict(p =>fsru_per_port[p]*new_pipeline_length[p]*pipeline_cost_per_km for p in port_set)
    total_capex = Dict(p => sum(infra_capex[p]/investment_horizon/(1 + (1-r))^t for t in 1:investment_horizon) + pipeline_capex[p] for p in port_set)
    port_opex = Dict(p => 0.025*(infra_capex[p])/max(1,fsru_per_port[p]) + lease_cost for p in port_set) # opex per fsru in use
    #FSRUs
    fsru_cap = Dict(fsru_set .=> 5) #bcm per year
    #all
    total_supply = sum(first.(values(countries_supply)))
    ##Demand
    if DEMAND == "Lin"
        TOTAL_DEMAND = range(86.7,0.,length(2022:2050))[2:end]
    elseif DEMAND == "NZE"
        forecast = [[(812+855)/2, 812, (794+812)/2]; range(794,582,length(2026:2030))] #23-30
        dec_rate = mean(diff(forecast))
        projection = [max(0., last(forecast)+dec_rate*t) for t in eachindex(2031:2050)]
        TOTAL_DEMAND = [forecast; projection] .* 0.1
    elseif DEMAND == "DEG"
        forecast = [86.0, 85.0, 82.0, 80.3, 78.7, 77.1, 75.5, 74.1] #23-29
        dec_rate = mean(diff(forecast))
        projection = [max(0., last(forecast)+dec_rate*t) for t in eachindex(2031:2050)]
        TOTAL_DEMAND = [forecast; projection] 
    else 
        error("Invalid DEMAND parameter \"$DEMAND\"")
    end
    demand_index = TOTAL_DEMAND ./ TOTAL_DEMAND[1]
    #Domestic
    DOMESTIC_PRODUCTION_CAPACITY = 4.68 #bcm per year
    domestic_production_capacity = Dict(n => DOMESTIC_PRODUCTION_CAPACITY*get_prop(g, n, :production_share) for n in producers_set)
    #export
    countries_demand = Dict("BE" => 0., "AT" => 8.03, "LU" => 0., "CZ" => 29.57, "CH" => 3.36, "FR" => 1.37, "PL" => 3.76, "FI" => 0., "DK" => 2.17, "NL" => 2.77) #bcm3 per year 
    total_export = sum(values(countries_demand))                                                  
    #domestic
    total_domestic_demand = 0.41.*TOTAL_DEMAND #bcm3 per year
    TOT = sum(get_prop(g, n, :gdp_percentage) for n in domestic_set)
    nodal_domestic_demand = Dict((n,t) => get_prop(g, n, :gdp_percentage)*total_domestic_demand[t]*1/TOT for n in domestic_set for t in 1:length(periods))
    #industrial
    total_industrial_demand = 0.59.*TOTAL_DEMAND #bcm3 per year
    nodal_industrial_demand = Dict((n,t) => get_prop(g, n, :demand_percentage)*total_industrial_demand[t] for n in consumers_set for t in 1:length(periods))
    #all demand 
    nodal_demand = merge(nodal_domestic_demand, nodal_industrial_demand)
    if !SILENT
        println("2022: total supply (imports) = $total_supply\ntotal domestic capacity = $DOMESTIC_PRODUCTION_CAPACITY\ntotal demand = $(TOTAL_DEMAND[1])\ntotal exports = $total_export\nleaving ", TOTAL_DEMAND[1] + total_export - total_supply-DOMESTIC_PRODUCTION_CAPACITY, " of capacity needed")
    end
end;