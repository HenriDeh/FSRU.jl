# FSRU
This repository accompagnies the Natural Gas Floating Storage and Regasification Units Deployment: A Europe Gas Network Application conference paper presented at the Twenty-third International Working Seminar on Production Economics (February 14-18, 2024). 

To reproduce the results, download this repository and install Julia (v1.10 or higher). Execute Julia at the location of this repository and type `include("reproduce_script.jl")` in the REPL. This will run both scenarios and generate the figures found in the Application and Results sections. 

# To generate an interactive map of the network
1. Launch Julia (1.10 or >)
2. Enter the following prompts
    1. `using Pkg`
    2. `Pkg.add("https://github.com/HenriDeh/FSRU_IWSPE")`
    3. `using FSRU`
    4. `generate_map_greenfield()`
Alternatively, use `generate_map_brownfield()` at step 4 to obtain the brownfield graph. 
Each step may take a while as the complete project is compiled and the the experiments are reproduced before creating the map. The map will pop in a dedicated interactive window. Use right-click to pan the map and the scroll wheel to zoom. Reset the zoom using Ctrl+left-click.