import PracticalBayesPlot as PBP
# The package exports nothing; bring its public names into scope.
using PracticalBayesPlot: Figure, Axis, Relative, current_axis,
    lines!, lines, scatter!, scatter, stairs!, stairs, band!, band,
    barplot!, barplot, hist!, hist, density!, density, ecdfplot!, ecdfplot,
    rangebars!, rangebars, hlines!, vlines!, text!,
    axislegend, xlims!, ylims!, limits!, colsize!, rowsize!,
    traceplot, densities, intervals, intervals!, ppcheck, ppcheck!,
    wong_colors, svg, save, preview
using Random, Test
using FlexiChains: FlexiChain, Parameter, Extra
using MCMCChains: Chains
using Tables: Tables

@testset "nothing is exported" begin
    m = Module()
    Core.eval(m, :(using PracticalBayesPlot))
    @test !any(n -> isdefined(m, n), (:Figure, :Axis, :lines!, :hist, :save, :svg, :preview))
end

# check that every tag in an SVG string is closed in order
function wellformed(s::AbstractString)
    stack = String[]
    for m in eachmatch(r"<(/?)([A-Za-z]+)[^>]*?(/?)>", s)
        closing, name, selfclosing = m.captures
        if closing == "/"
            (isempty(stack) || pop!(stack) != name) && return false
        elseif selfclosing != "/"
            push!(stack, name)
        end
    end
    return isempty(stack)
end

count_of(s, pat) = length(collect(eachmatch(pat, s)))

# stands in for VS Code's or IJulia's display, which can show SVG
struct FakeSVGDisplay <: AbstractDisplay
    shown::Vector{Any}
end
Base.displayable(::FakeSVGDisplay, ::MIME"image/svg+xml") = true
Base.display(d::FakeSVGDisplay, ::MIME"image/svg+xml", x) = (push!(d.shown, x); nothing)

@testset "PracticalBayesPlot" begin
    @testset "ticks" begin
        t, d = PBP.nice_ticks(0.0, 1.0, 5)
        @test t ≈ 0:0.2:1
        @test d == 1
        t, d = PBP.nice_ticks(-3.7, 12.2, 5)
        @test all(-3.7 .<= t .<= 12.2)
        @test 4 <= length(t) <= 8
        @test PBP.fmt_tick(0.0, 1) == "0.0"
        @test PBP.fmt_tick(0.30000000000000004, 1) == "0.3"
        @test PBP.fmt_tick(-2.0, 0) == "−2"
        @test PBP.fmt_tick(0.25, 2) == "0.25"
        @test PBP.fmt_tick(2.0e7, 0) == "2e7"
        @test isempty(first(PBP.nice_ticks(1.0, 1.0, 5)))
    end

    @testset "colours" begin
        @test PBP.paint(:steelblue, 1.0) == PBP.Paint("steelblue", 1.0)
        @test PBP.paint((:red, 0.25), 1.0) == PBP.Paint("red", 0.25)
        @test PBP.paint(2, 0.5) == PBP.Paint(wong_colors()[2], 0.5)
        @test PBP.paint((1, 0, 0), 1.0).css == "rgb(255,0,0)"
        @test !PBP.isvisible(PBP.paint(:transparent, 1.0))
        @test !PBP.isvisible(PBP.paint((:white, 0.0), 1.0))
        @test_throws ArgumentError PBP.paint(1.5, 1.0)
    end

    @testset "statistics" begin
        x = collect(range(-3, 3; length=2001))
        v = [sin(i)^3 for i in 1:500]
        d = PBP.kde(v, x)
        @test sum(d) * step(range(-3, 3; length=2001)) ≈ 1 atol = 0.01
        @test PBP._quantile_sorted([1.0, 2.0, 3.0, 4.0], 0.5) == 2.5
        @test PBP._bincounts([0.0, 0.5, 1.0], [0.0, 0.5, 1.0]) == [1.0, 2.0]
    end

    @testset "every plot type renders" begin
        fig = Figure(; title="all & everything")
        ax = Axis(fig[1, 1]; xlabel="x <1>", ylabel="y", title="t")
        x = collect(range(0, 1; length=20))
        lines!(ax, x, x .^ 2; label="line")
        lines!(ax, [0.0, 0.5, NaN, 0.6, 1.0], [0.0, 0.1, 0.2, 0.3, 0.4])
        stairs!(ax, x, x; step=:center)
        scatter!(ax, x, x; marker=:utriangle, label="pts")
        band!(ax, x, x .- 0.1, x .+ 0.1)
        hlines!(ax, 0.5; linestyle=:dash)
        vlines!(ax, [0.2, 0.4])
        text!(ax, 0.5, 0.5; text="note", align=(:center, :center))
        density!(ax, x)
        ecdfplot!(ax, x)
        axislegend(ax, "key"; position=:rb)
        ax2 = Axis(fig[1, 2])
        hist!(ax2, randn(500); normalization=:pdf, bins=20, label="h")
        barplot!(ax2, [1, 2, 3], [1, 2, 3])
        rangebars!(ax2, 1:3, zeros(3), ones(3); whiskerwidth=5)
        s = svg(fig)
        @test wellformed(s)
        @test startswith(s, "<svg")
        @test occursin("all &amp; everything", s)
        @test occursin("x &lt;1&gt;", s)
        @test occursin(">key<", s) && occursin(">line<", s) && occursin(">pts<", s)
        @test !occursin("NaN", s) && !occursin("Inf", s)
        @test count_of(s, r"<clipPath") == 2
        @test sprint(show, MIME"image/svg+xml"(), fig) |> wellformed
        @test sprint(show, fig) == "Figure(600×450, 2 axes)"
    end

    @testset "NaN breaks a line" begin
        fig = lines([1.0, 2.0, NaN, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0, 5.0])
        s = svg(fig)
        path = match(r"<path d=\"(M[^\"]*)\" fill=\"none\" stroke=\"#0072B2\"", s)
        @test path !== nothing
        @test count(==('M'), path.captures[1]) == 2
    end

    @testset "categories" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        barplot!(ax, ["low", "mid", "high"], [1, 3, 2])
        scatter!(ax, ["mid", "top"], [3.5, 1.0])
        @test ax.xcategories == ["low", "mid", "high", "top"]
        s = svg(fig)
        @test occursin(">low<", s) && occursin(">top<", s)
        ax2 = Axis(fig[2, 1])
        rangebars!(ax2, ["a", "b"], [0, 1], [1, 2]; direction=:x)
        @test ax2.ycategories == ["a", "b"]
        @test wellformed(svg(fig))
    end

    @testset "limits and ticks" begin
        fig = Figure()
        ax = Axis(fig[1, 1]; yticks=([0, 1], ["zero", "one"]))
        lines!(ax, [0, 10], [0, 1])
        xlims!(ax, 0, 5)
        @test PBP._limits(ax)[1:2] == (0.0, 5.0)
        s = svg(fig)
        @test occursin(">zero<", s) && occursin(">one<", s)
        @test !occursin(">10<", s)
        ax.limits = ((nothing, 20), nothing)
        @test PBP._limits(ax)[2] == 20.0
        @test isnan(ax.limits[1])
        # bars start at zero
        ax3 = Axis(fig[2, 1])
        barplot!(ax3, [1, 2], [2, 3])
        @test PBP._limits(ax3)[3] == 0.0
    end

    @testset "layout" begin
        fig = Figure(; size=(800, 600))
        a = Axis(fig[1, 1]; ylabel="a long y label")
        b = Axis(fig[2, 1])
        c = Axis(fig[1:2, 2])
        for ax in (a, b, c)
            lines!(ax, [1, 2], [1, 1000])
        end
        colsize!(fig, 1, Relative(0.7))
        s = svg(fig)
        @test wellformed(s)
        @test count_of(s, r"<clipPath") == 3
        # the two axes in column 1 share their left edge
        xs = [parse(Float64, m.captures[1]) for m in eachmatch(r"<clipPath id=\"[^\"]+\"><rect x=\"([0-9.]+)\"", s)]
        @test xs[1] == xs[2]
        @test xs[3] > 0.6 * 800
    end

    @testset "errors" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        @test_throws DimensionMismatch lines!(ax, 1:3, 1:4)
        @test_throws ArgumentError lines!(ax, 1:3, 1:3; linestyle=:wiggly)
        @test_throws ArgumentError scatter!(ax, 1:3, 1:3; marker=:star)
        @test_throws ArgumentError hist!(ax, [NaN])
        @test_throws ArgumentError hist!(ax, 1:3; normalization=:area)
        @test_throws ArgumentError axislegend(ax; position=:top)
        @test_throws ArgumentError fig[0, 1]
        @test_throws ArgumentError save("figure.png", fig)
    end

    @testset "one-call forms and current axis" begin
        fig = hist(randn(100); bins=10, axis=(; xlabel="v"), figure=(; size=(300, 200)))
        @test fig isa Figure
        @test fig.size == (300, 200)
        @test current_axis().xlabel == "v"
        lines!(1:3, [1, 2, 3])
        @test length(current_axis().plots) == 2
        hlines!(0.0)
        @test length(current_axis().plots) == 3
    end

    @testset "save" begin
        fig = scatter(randn(10), randn(10))
        dir = mktempdir()
        p = save(joinpath(dir, "f.svg"), fig)
        @test wellformed(read(p, String))
        p = save(joinpath(dir, "f.html"), fig)
        @test occursin("<svg", read(p, String))
    end

    @testset "display hook" begin
        shown = Any[]
        fake = FakeSVGDisplay(shown)
        pushdisplay(fake)
        pushdisplay(PBP.BrowserDisplay())
        try
            fig = lines(1:3, 1:3)
            display(fig)
            @test length(shown) == 1 && shown[1] === fig
            # other objects fall through to the displays below
            @test_throws MethodError display(PBP.BrowserDisplay(), 1)
        finally
            popdisplay()
            popdisplay()
        end
    end

    @testset "PracticalBayesianRegression plots" begin
        include(joinpath(@__DIR__, "..", "examples", "pbr_plots.jl"))
        for (name, fig) in Base.invokelatest(gallery)
            s = svg(fig)
            @test wellformed(s)
            @test !occursin("NaN", s)
        end
    end

    @testset "reading draws" begin
        names_sizes(d) = (first.(d), size.(last.(d)))
        @test names_sizes(PBP.todraws(randn(10))) == (["θ"], [(10, 1)])
        @test names_sizes(PBP.todraws(randn(10, 2))) == (["θ[1]", "θ[2]"], [(10, 1), (10, 1)])
        @test names_sizes(PBP.todraws(randn(10, 2, 3))) == (["θ[1]", "θ[2]"], [(10, 3), (10, 3)])
        a = reshape(collect(1.0:20.0), 10, 2)
        @test PBP.todraws((; a))[1] == ("a" => a)
        @test names_sizes(PBP.todraws(["a" => a, :b => randn(10)])) == (["a", "b"], [(10, 2), (10, 1)])
        @test names_sizes(PBP.todraws(Dict("a" => a))) == (["a"], [(10, 2)])
        @test names_sizes(PBP.todraws("a" => a)) == (["a"], [(10, 2)])
        # columns: the chain column splits draws, index and non-numeric columns are dropped
        cols = (; chain=repeat([1, 2]; inner=10), iteration=repeat(1:10, 2), a=vec(a), g=fill("x", 20))
        @test PBP.todraws(cols) == ["a" => a]
        @test_throws ArgumentError PBP.todraws((; chain=[1, 1, 2], a=[1.0, 2.0, 3.0]))
        @test_throws ArgumentError PBP.todraws(:x)
        @test_throws ArgumentError traceplot((; a); variables=["b"])
        @test first.(PBP._select(PBP.todraws((; a, b=a, c=a)), [:c, "a"])) == ["c", "a"]
    end

    @testset "Bayesian workflow plots" begin
        rng = Xoshiro(2)
        draws = (; mu=randn(rng, 200, 4), sigma=exp.(0.1 .* randn(rng, 200, 4)))
        s = svg(traceplot(draws))
        @test wellformed(s) && occursin(">mu<", s) && occursin(">sigma<", s)
        @test count_of(s, r"<clipPath") == 4                         # 2 parameters × (trace, density)
        @test count_of(svg(traceplot(draws; density=false, variables="mu")), r"<clipPath") == 1
        s = svg(densities(draws; combine=true))
        @test wellformed(s) && count_of(s, r"<clipPath") == 2
        @test count_of(svg(densities(randn(rng, 50, 7); ncols=2)), r"<clipPath") == 7
        fig = intervals(draws)
        @test wellformed(svg(fig))
        ax = fig.axes[1]
        @test ax.ycategories == ["sigma", "mu"]                       # first parameter at the top
        bars = filter(p -> p isa PBP.RangeBarsPlot, ax.plots)
        @test length(bars) == 2 && bars[1].horizontal
        # 90% interval of mu contains its 50% interval
        @test bars[1].lo[2] < bars[2].lo[2] < bars[2].hi[2] < bars[1].hi[2]
        ax2 = Axis(Figure()[1, 1])
        intervals!(ax2, draws; prob=0.8, point=PBP.mean, color=:red)
        @test length(ax2.plots) == 3
        @test_throws ArgumentError intervals(draws; prob=1.5)

        y = randn(rng, 80)
        yrep = randn(rng, 30, 80)
        for type in (:dens_overlay, :ecdf_overlay, :hist, :stat)
            s = svg(ppcheck(y, yrep; type))
            @test wellformed(s) && !occursin("NaN", s)
        end
        @test occursin("T = mean", svg(ppcheck(y, yrep; type=:stat)))
        @test occursin("T = maximum", svg(ppcheck(y, yrep; type=:stat, stat=maximum)))
        s = svg(ppcheck(rand(rng, 0:4, 80), rand(rng, 0:4, 30, 80); type=:bars))
        @test wellformed(s) && occursin(">y_rep<", s)
        fig = ppcheck(y, yrep; axis=(; xlabel="weight"))
        @test fig.axes[1].xlabel == "weight" && fig.axes[1].ylabel == "density"
        @test_throws DimensionMismatch ppcheck(y, randn(rng, 30, 79))
        @test_throws ArgumentError ppcheck(y, yrep; type=:violin)
    end

    @testset "extensions" begin
        rng = Xoshiro(3)
        @testset "FlexiChains" begin
            fc = FlexiChain{Symbol}(50, 3, Dict(Parameter(:mu) => randn(rng, 50, 3),
                                                Parameter(:x) => [randn(rng, 2) for _ in 1:50, _ in 1:3],
                                                Parameter(:label) => fill("a", 50, 3),
                                                Extra(:lp) => randn(rng, 50, 3)))
            d = PBP.todraws(fc)
            @test sort(first.(d)) == ["mu", "x[1]", "x[2]"]
            @test all(m -> size(m) == (50, 3), last.(d))
            @test Dict(d)["x[2]"] == [v[2] for v in fc[Parameter(:x)]]
            @test wellformed(svg(traceplot(fc; variables=["mu"])))
        end
        @testset "MCMCChains" begin
            vals = randn(rng, 40, 3, 2)
            mc = Chains(vals, [:a, Symbol("b[1]"), :lp], Dict(:internals => [:lp]))
            d = PBP.todraws(mc)
            @test first.(d) == ["a", "b[1]"]
            @test last(d[2]) == vals[:, 2, :]
            @test wellformed(svg(intervals(mc)))
        end
        @testset "Tables" begin
            rows = [(; chain=c, draw=i, mu=Float64(i + 100c)) for c in 1:2 for i in 1:5]
            @test Tables.istable(rows)
            d = PBP.todraws(rows)
            @test d == ["mu" => Float64[i + 100c for i in 1:5, c in 1:2]]
            @test wellformed(svg(densities(rows)))
            @test_throws ArgumentError PBP.todraws([:not, :a, :table])
        end
    end
end
