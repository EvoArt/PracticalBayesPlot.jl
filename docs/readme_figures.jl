# Runs the code blocks of README.md that follow a `<!-- figure: name -->`
# marker, in order and in one module, and saves each block's `fig` to
# docs/src/assets/name.svg. The README shows those files, so the pictures
# always come from the code printed next to them.
#
#     julia --project=docs docs/readme_figures.jl

using PracticalBayesPlot

function readme_figures(readme=joinpath(@__DIR__, "..", "README.md"),
                        assets=joinpath(@__DIR__, "src", "assets"))
    mkpath(assets)
    text = read(readme, String)
    blocks = eachmatch(r"<!-- figure: ([\w-]+) -->\s*```julia\n(.*?)```"s, text)
    mod = Module(:ReadmeExamples)
    Core.eval(mod, :(include(path) = Base.include($mod, path)))
    written = String[]
    cd(mktempdir()) do  # blocks may save files of their own
        for m in blocks
            name, code = m.captures
            Base.include_string(mod, code, "README.md[$name]")
            fig = Core.eval(mod, :fig)
            push!(written, PracticalBayesPlot.save(joinpath(assets, name * ".svg"), fig))
        end
    end
    isempty(written) && error("no `<!-- figure: name -->` blocks found in $readme")
    return written
end

if abspath(PROGRAM_FILE) == @__FILE__
    foreach(println, readme_figures())
end
