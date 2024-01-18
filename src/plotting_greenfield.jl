include("graph_plotting.jl")
FSRU.GLMakie.activate!(inline=false)

de_map = map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs)
save("de_map.png", de_map)

FSRU.GLMakie.activate!(inline=true)
imports = [c => [round(sum(value(import_flow[n,t]) for n in nodes), digits = 3) for t in periods] for (c, nodes) in import_countries_set]
sort!(imports, by = p -> first(p.second), rev = true)
f = Figure(resolution = (2560, 1440)./3);
ax=Axis(f[1, 1], xlabel = "Year", ylabel = "bcm", xticks = (collect(1:3:length(periods)), string.(collect(2023:3:2050))))
for (i,(c, ys)) in enumerate(imports) 
    colors = [Makie.wong_colors(); [:green, :darkblue, :lightgreen]]
    if first(ys) > 0
        lines!(periods, ys, label = c, color = colors[i], linestyle = c in ("NL", "BE", "FR") ? :dash : :solid, linewidth = c in ("NL", "BE", "FR") ? 3 : 2)
    end
end
f[1,2] = Legend(f, ax, "Country")
display(f)
save("pipeline_imports_free.png", f)

fsru_imports = [c => round.(value.(fsru_flow)[n,:], digits =2).data for (c,n) in port_dict]
sort!(fsru_imports, by = p -> first(p.second), rev = true)
f = Figure(resolution = (2560, 1440)./3);
ax=Axis(f[1, 1], xlabel = "Year", ylabel = "bcm", xticks = (collect(1:3:length(periods)), string.(collect(2023:3:2050))))
for (c, ys) in fsru_imports 
    if sum(ys) > 0
        lines!(periods, ys, label = c, linewidth = 2)
    end
end
f[1,2] = Legend(f, ax, "Port")
display(f)
save("fsru_imports_free.png", f)

#pipe_capacity(path) = minimum(props(g, path[i], path[i+1])[:capacity_Mm3_per_d] for i in eachindex(path)[1:end-1])=#