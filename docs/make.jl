#     julia --project=docs docs/make.jl

using Documenter
using PracticalBayesPlot

# Redraw the README figures, then use the README as the landing page so the
# examples are written once.
include(joinpath(@__DIR__, "readme_figures.jl"))
readme_figures()

readme = read(joinpath(@__DIR__, "..", "README.md"), String)
index = replace(readme, "docs/src/assets/" => "assets/", r"<!-- figure: [\w-]+ -->\n" => "")
write(joinpath(@__DIR__, "src", "index.md"),
      "```@meta\nEditURL = \"../../README.md\"\n```\n\n", index)

makedocs(;
    sitename = "PracticalBayesPlot.jl",
    modules = [PracticalBayesPlot],
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    pages = ["Home" => "index.md", "API" => "api.md"],
    checkdocs = :public,
)

deploydocs(; repo = "github.com/EvoArt/PracticalBayesPlot.jl.git", devbranch = "main")
