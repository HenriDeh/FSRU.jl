if !BROWNFIELD
    include("graph_plotting.jl")
    FSRU.GLMakie.activate!(inline=true)

    de_map = map_network(g, consumers_dict, domestic_dict, port_dict, import_dict, export_dict, ports_coordinates, highlight_arcs = penalized_arcs)
    save("de_map.png", de_map)
end

colors = [Makie.wong_colors(); [:green, :darkblue, :lightgreen]]
imports = [c => [round(sum(value(import_flow[n,t]) for n in nodes), digits = 3) for t in periods] for (c, nodes) in import_countries_set]
sort!(imports, by = p -> first(p.second), rev = true)
f = Figure(size = (2560, 1000)./3);
ax=Axis(f[1, 1], xlabel = "Year", ylabel = "bcm", xticks = (collect(1:3:length(periods)), string.(collect(2023:3:2050))), yscale = Makie.pseudolog10, yticks = [0,5,10,20,40,60])
for (i,(c, ys)) in enumerate(imports) 
    if first(ys) > 0
        lines!(periods, ys, label = c, color = colors[i], linestyle = c in ("NL", "BE", "FR") ? :dash : :solid, linewidth = c in ("NL", "BE", "FR") ? 3 : 2)
    end
end
f[1,2] = Legend(f, ax, "Country", margin = (0, 0, 0, 0), halign = :left, valign = :center, tellheight = false, tellwidth = true)
display(f)
if BROWNFIELD
    save("pipeline_imports_res.png", f)
else
    save("pipeline_imports_free.png", f)
end

fsru_imports = [c => round.(value.(fsru_flow)[n,:], digits =2).data for (c,n) in port_dict if sum(value.(fsru_flow)[n,:]) > 0]
sort!(fsru_imports, by = p -> first(p.second), rev = false)
f = Figure(size = (2560, 1000)./3);
ax=Axis(f[1, 1], xlabel = "Year", ylabel = "bcm", limits = ((0, length(2022:2050)),(0,37)), xticks = (collect(1:3:length(periods)), string.(collect(2023:3:2050))))
tbl = (year=Int[],country=String[], imports=Float64[], stackgrp=Int[])
for (i,(c, ys)) in enumerate(fsru_imports)
    if sum(ys) > 0
        for (t,y) in enumerate(ys)
            push!(tbl.year, t)
            push!(tbl.country, c)
            push!(tbl.stackgrp, i)
            push!(tbl.imports, y)
        end
    end
end
barplot!(ax,tbl.year, tbl.imports, stack = tbl.stackgrp, label = tbl.country, color = [colors[g] for g in tbl.stackgrp])
Legend(f[1,1], reverse([PolyElement(polycolor = colors[i]) for i in 1:length(unique(tbl.country))]), reverse(unique(tbl.country)), "Port", margin = (10, 10, 10, 10), halign = :right, valign = :top, tellheight = false, tellwidth = false)
display(f)
if BROWNFIELD
    save("fsru_imports_res.png", f)
else
    save("fsru_imports_free.png", f)
end
