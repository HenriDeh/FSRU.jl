using GLMakie, CairoMakie, Colors
if scenario_num == 3
    include("graph_plotting.jl")
    CairoMakie.activate!()
    de_map = map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs)
    save("de_map.png", de_map)
end
CairoMakie.activate!()

idxs = [(1,1), (2,1), (3, 1), (1, 2), (2,2), (3,2)]
colors = [Makie.wong_colors(); [RGB(Colors.color_names[c]./255...) for c in string.([:green, :darkblue, :lightgreen, :firebrick3])]]
colors[2] = RGB(0,0,0)
countries = sort(collect(keys(import_countries_set)))
push!(countries, "DE (prod.)")
color_ids = Dict(c => colors[i] for (i,c) in enumerate(countries))
style_ids = Dict(c => c in ("NL", "BE", "FR", "CH") ? (:dot, :dense) : :solid for c in countries)

imports = [c => [round(sum(value(import_flow[n,t]) for n in nodes), digits = 3) for t in periods] for (c, nodes) in import_countries_set]
sort!(imports, by = p -> first(p.first), rev = false)
push!(imports, "DE (prod.)" =>  round.([sum(value(nodal_production[n,t]) for n in producers_set) for t in periods],digits=2))
if scenario_num == 1
    aximports = []
    fimports = Figure(size = (2560, 1000*3)./3);
end
push!(aximports, Axis(fimports[idxs[scenario_num]...], xlabel = "Year", ylabel = "bcm", title = scenario_name, xticks = (collect(1:3:length(periods)), [y[3:4] for y in string.(collect(2023:3:2050))]), yscale = Makie.pseudolog10, yticks = [0,1,2,3,4,5,10,20,40,60]))
for (i,(c, ys)) in enumerate(imports) 
    lines!(last(aximports), periods, replace(x->x <= 0. ? NaN : x, ys), label = c, color = color_ids[c], linestyle = style_ids[c], linewidth = c in ("NL", "BE", "FR", "CH") ? 3 : 2)
end
# if scenario_num >= 4
#     hideydecorations!(last(aximports), grid = false)
# end
# if scenario_num ∉ (3,6)
#     hidexdecorations!(last(aximports), grid = false)
# end
if scenario_num == 6
    fimports[:,3] = Legend(fimports, aximports[1], "Country", margin = (0, 0, 0, 0), halign = :left, valign = :center, tellheight = false, tellwidth = true)
    linkaxes!(aximports...)
end
if scenario_num == 6
    display(fimports)
    save("pipeline_imports.png", fimports)
end

###FSRU###
if scenario_num == 1
    ffsru = Figure(size = (2000, 1000*4)./3);
    axfsru = []
end
if scenario_num != 5
    f = ffsru
    axes = axfsru
    j = findfirst(==(scenario_num), [1,2,3,4,6])
end
if scenario_num != 5
    all_ports = sort(collect(keys(port_dict)))
    color_ids = Dict(p => i for (i,p) in enumerate(all_ports))
    fsru_imports = [p => round.(value.(fsru_flow)[n,:], digits =2).data for (p,n) in port_dict] # if value.(port_upgraded)[n, end] == 1]
    sort!(fsru_imports, by = p -> first(p.first), rev = false)

    push!(axes, Axis(f[j,1], xlabel = "Year", ylabel = "bcm", title = scenario_name, limits = ((0, length(2022:2050)),(0,50)), xticks = (collect(1:3:length(periods)), [y[3:4] for y in string.(collect(2023:3:2050))])))
    tbl = (year=Int[],port=String[], imports=Float64[], stackgrp=Int[])
    for (i,(p, ys)) in collect(enumerate(fsru_imports))
        for (t,y) in enumerate(ys)
            push!(tbl.year, t)
            push!(tbl.port, p)
            push!(tbl.stackgrp, i)
            push!(tbl.imports, y)
        end
    end
    barplot!(last(axes), tbl.year, tbl.imports, stack = tbl.stackgrp, label = tbl.port, color = [colors[color_ids[g]] for g in tbl.port])
    upgraded_ports = sort([p for (p,n) in port_dict if sum(round.(value.(port_upgrade))[n, :]) > 0])
    Legend(f[j,2], [PolyElement(polycolor = colors[color_ids[p]]) for p in upgraded_ports], upgraded_ports, "Upgraded ports", margin = (10, 10, 10, 10), halign = :right, valign = :center, tellheight = false, tellwidth = true)
    # if scenario_num != 6
    #     hidexdecorations!(last(axfsru), grid = false)
    # end
    linkaxes!(axfsru...)#, axappend...)
end
if scenario_num == 6
    display(ffsru)
    save("fsru_imports.png", ffsru)
end
# if scenario_num == 2
#     save("fsru_imports_appendix.png", fappend)
# end
