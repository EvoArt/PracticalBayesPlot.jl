# Run every plot type once while the package is precompiled, so the native
# code is cached and the first plot in a session is fast.

function _workload()
    x = collect(range(0.0, 1.0; length=30))
    y = x .^ 2
    m = reshape(collect(1.0:60.0), 2, 30)
    fig = Figure(; size=(600, 450), title="workload")
    ax = Axis(fig[1, 1]; xlabel="x", ylabel="y", title="t")
    lines!(ax, x, y; color=(:steelblue, 0.25), linewidth=0.8)
    lines!(ax, x, view(m, 1, :); color=:black, linewidth=2.5, label="y")
    lines!(ax, 1:30, collect(1:30); color=2, linestyle=:dash)
    lines!(ax, y)
    lines!(ax, range(0.0, 1.0; length=2), view(m, :, 3))
    lines!(ax, collect(1:30), view(m, 1, :); color="red", label=:a)
    stairs!(ax, x, y; color=(:steelblue, 0.25))
    stairs!(ax, x, y; step=:post, color="#000000", linewidth=2.5)
    density!(ax, y; color=(:steelblue, 0.25), linewidth=0.8)
    density!(ax, view(m, 2, :))
    ecdfplot!(ax, y; color=:black)
    band!(ax, x, y .- 0.1, y .+ 0.1; color=((0.1, 0.2, 0.3), 0.25))
    band!(ax, 1:30, y, y)
    scatter!(ax, x, y; color=(:steelblue, 0.5), markersize=5)
    scatter!(ax, x, y; marker=:diamond, strokewidth=1)
    hlines!(ax, [0.0]; color=:black, linestyle=:dash)
    hlines!(ax, 0.5)
    vlines!(ax, [0.5]; color=:black, linewidth=3)
    text!(ax, 0.5, 0.5; text="a")
    axislegend(ax, "g"; position=:lt)

    ax2 = Axis(fig[1, 2])
    hist!(ax2, y; normalization=:pdf, color=(:steelblue, 0.25), bins=40)
    hist!(ax2, x; normalization=:pdf, color=(:white, 0.0), strokecolor=:black, strokewidth=1.5, bins=40)
    hist!(ax2, collect(1:10))
    ax2.xlabel = "T = mean"

    ax3 = Axis(fig[2, 1:2])
    barplot!(ax3, [1.0, 2.0, 3.0], [3, 1, 2]; color=(:steelblue, 0.6))
    barplot!(ax3, ["a", "b", "c"], [3.0, 1.0, 2.0])
    rangebars!(ax3, [1.0, 2.0, 3.0], [0.5, 0.5, 0.5], [2.5, 2.5, 2.5]; color=:black)
    rangebars!(ax3, 1:3, [0.5, 0.5, 0.5], [2.5, 2.5, 2.5]; color=1, whiskerwidth=6)
    scatter!(ax3, [1, 2, 3], [1.0, 2.0, 1.5]; color=:black)
    ax3.xticks = (collect(1:3), string.(["a", "b", "c"]))
    ax3.limits = (nothing, nothing, 0, nothing)
    colsize!(fig, 1, Relative(0.7))

    ax4 = Axis(fig[3, 1])
    rangebars!(ax4, ["b_x", "sigma"], [0.1, 0.2], [0.3, 0.4]; direction=:x)
    scatter!(ax4, [0.2, 0.3], ["b_x", "sigma"])

    io = IOBuffer()
    show(io, MIME"image/svg+xml"(), fig)
    svg(fig)
    show(io, fig)
    svg(lines(x, y; axis=(; xlabel="x")))
    svg(scatter(x, y))
    svg(hist(y))
    svg(density(y))
    tmp = tempname()
    rm(save(tmp * ".svg", fig))
    rm(save(tmp * ".html", fig))

    # Bayesian workflow plots, from the most common forms of draws (chains
    # arrive as Draws, through the extensions)
    nt = (; a=reshape(collect(range(0.0, 1.0; length=40)), 20, 2), b=reshape(sin.(1.0:40.0), 20, 2))
    arr = reshape(cos.(1.0:120.0), 20, 3, 2)
    yrep = reshape(sin.(1.0:60.0) .+ 0.5, 3, 20)
    svg(traceplot(nt))
    svg(densities(arr))
    svg(intervals(nt))
    for type in (:dens_overlay, :ecdf_overlay, :hist, :stat)
        svg(ppcheck(y[1:20], yrep; type))
    end
    CURRENT[] = nothing
    return nothing
end

# Tagging makes Julia keep the native code of everything inferred during the
# workload, including Base methods specialised on our types (the mechanism
# PrecompileTools uses, without the dependency). Julia 1.12 needs this;
# earlier versions cache the workload without it and lack the hook.
if ccall(:jl_generating_output, Cint, ()) == 1
    @static if VERSION >= v"1.12.0-"
        ccall(:jl_tag_newly_inferred_enable, Cvoid, ())
        try
            _workload()
        finally
            ccall(:jl_tag_newly_inferred_disable, Cvoid, ())
        end
    else
        _workload()
    end
end

# The public functions are @nospecialize, so one keyword-call instance of
# each serves every argument type; make sure those instances are cached.
if ccall(:jl_generating_output, Cint, ()) == 1
    for (f, nargs) in ((lines!, 2), (lines!, 1), (stairs!, 2), (stairs!, 1), (scatter!, 2), (scatter!, 1),
                       (band!, 3), (barplot!, 2), (barplot!, 1), (hist!, 1), (density!, 1), (ecdfplot!, 1),
                       (rangebars!, 3), (hlines!, 1), (vlines!, 1), (text!, 2))
        precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(f), Axis, ntuple(_ -> Any, nargs)...})
        precompile(Tuple{typeof(f), Axis, ntuple(_ -> Any, nargs)...})
    end
    for f in (lines, scatter, stairs, band, barplot, hist, density, ecdfplot, rangebars)
        precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(f), Vararg{Any}})
    end
    for f in (traceplot, densities, intervals)
        precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(f), Any})
        precompile(Tuple{typeof(f), Any})
    end
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(intervals!), Axis, Any})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(ppcheck), Any, Any})
    precompile(Tuple{typeof(ppcheck), Any, Any})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(ppcheck!), Axis, Any, Any})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, Type{Axis}, GridPos})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, Type{Figure}})
    precompile(Tuple{Type{Figure}})
    precompile(Tuple{typeof(getindex), Figure, Int, Int})
    precompile(Tuple{typeof(svg), Figure})
    precompile(Tuple{typeof(svg), IOBuffer, Figure})
    precompile(Tuple{typeof(save), String, Figure})
    precompile(Tuple{typeof(preview), Figure})
    precompile(Tuple{typeof(display), BrowserDisplay, Figure})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(axislegend), Axis})
    precompile(Tuple{typeof(Core.kwcall), NamedTuple, typeof(axislegend), Axis, String})
end
