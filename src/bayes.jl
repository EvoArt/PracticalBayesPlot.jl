# Plots for the Bayesian workflow, built from the Makie-style primitives:
# trace plots, posterior densities, interval plots and posterior predictive
# checks. The functions that take posterior draws read them with `todraws`,
# which the package extensions (FlexiChains, MCMCChains, Tables) and other
# packages extend for their own types.

const YCOLOR = :black
const REPCOLOR = (:steelblue, 0.25)

const Draws = Vector{Pair{String,Matrix{Float64}}}

# --- reading draws ---------------------------------------------------------------

"""
    todraws(x) -> Vector{Pair{String,Matrix{Float64}}}

The posterior draws in `x` as `name => draws` pairs, where `draws` is an
iterations × chains matrix. [`traceplot`](@ref), [`densities`](@ref) and
[`intervals`](@ref) read their input with it, so a method for a new type
makes all of them accept that type.

`x` can be

- a vector: one parameter, one chain;
- a matrix: iterations × parameters, one chain;
- a 3-d array: iterations × parameters × chains (MCMCChains' layout);
- a `NamedTuple`, an `AbstractDict` or a vector of pairs `name => draws`,
  where each `draws` is a vector (one chain) or an iterations × chains matrix;
- with the package loaded, a `FlexiChains.FlexiChain`, an
  `MCMCChains.Chains`, or any Tables.jl table, such as a `DataFrame`.

In a table, or a `NamedTuple` or dictionary of vectors, each numeric column
is a parameter. A `chain` (or `.chain`) column splits the draws into chains;
`iteration`, `iter`, `draw`, `.iteration` and `.draw` columns are ignored.

Parameters without names are called `θ[1]`, `θ[2]`, ....
"""
function todraws end

const _CHAIN_COLUMNS = ("chain", ".chain")
const _INDEX_COLUMNS = ("iteration", "iter", "draw", ".iteration", ".draw")

todraws(x::Draws) = x
todraws(x::AbstractVector{<:Real}) = Pair{String,Matrix{Float64}}["θ" => reshape(_f64(x), :, 1)]
todraws(x::AbstractMatrix{<:Real}) =
    Pair{String,Matrix{Float64}}["θ[$j]" => reshape(_f64(view(x, :, j)), :, 1) for j in axes(x, 2)]
todraws(x::AbstractArray{<:Real,3}) =
    Pair{String,Matrix{Float64}}["θ[$j]" => Matrix{Float64}(view(x, :, j, :)) for j in axes(x, 2)]
# Each NamedTuple is its own type, so read its fields with builtins rather
# than iterating it, which would compile code for every new NamedTuple type.
function todraws(@nospecialize(x::NamedTuple))
    T = typeof(x)
    return _named_draws(String[string(fieldname(T, i)) for i in 1:nfields(x)], Any[getfield(x, i) for i in 1:nfields(x)])
end
todraws(@nospecialize(x::AbstractDict)) = _named_draws(_pairs_namesvals(x)...)
todraws(@nospecialize(x::AbstractVector{<:Pair})) = _named_draws(_pairs_namesvals(x)...)
todraws(@nospecialize(x::Pair)) = _named_draws([string(first(x))], Any[last(x)])

function _pairs_namesvals(@nospecialize(x))
    names, vals = String[], Any[]
    for p in x
        push!(names, string(p.first))
        push!(vals, p.second)
    end
    return names, vals
end

function todraws(x)
    hasmethod(_table_draws, Tuple{Any}) && return _table_draws(x)
    throw(ArgumentError("cannot read posterior draws from a $(typeof(x)); see `PracticalBayesPlot.todraws` " *
                        "for what can be read (tables need Tables.jl, chains FlexiChains or MCMCChains, loaded)"))
end

# a method is added by the Tables extension
function _table_draws end

function _named_draws(names::Vector{String}, vals::Vector{Any})
    all(v -> v isa AbstractVector, vals) && return _column_draws(names, vals)
    return Pair{String,Matrix{Float64}}[n => _drawmatrix(n, v) for (n, v) in zip(names, vals)]
end

function _drawmatrix(name::String, v)
    v isa AbstractVector && return reshape(_f64(v), :, 1)
    v isa AbstractMatrix && return Matrix{Float64}(v)
    throw(ArgumentError("the draws of `$name` must be a vector (one chain) or an iterations × chains " *
                        "matrix; got a $(typeof(v))"))
end

_isrealcol(c) = eltype(c) <: Real || all(v -> v isa Real, c)

"""
    _column_draws(names, cols)

Draws from table columns: every numeric column except the chain and
iteration columns is a parameter, split into chains by the chain column.
"""
function _column_draws(names::Vector{String}, cols::Vector{Any})
    k = findfirst(in(_CHAIN_COLUMNS), names)
    keep = [i for i in eachindex(names) if i != k && !(names[i] in _INDEX_COLUMNS) && _isrealcol(cols[i])]
    isempty(keep) && throw(ArgumentError("no numeric columns of draws found among $(join(names, ", "))"))
    if k === nothing
        return Pair{String,Matrix{Float64}}[names[i] => reshape(_f64(cols[i]), :, 1) for i in keep]
    end
    chain = cols[k]
    all(i -> length(cols[i]) == length(chain), keep) ||
        throw(DimensionMismatch("the draws columns and the chain column must have the same length"))
    ids = unique(chain)
    rows = [findall(isequal(c), chain) for c in ids]
    niter = length(rows[1])
    all(r -> length(r) == niter, rows) ||
        throw(ArgumentError("every chain must have the same number of draws; got $(join(length.(rows), ", "))"))
    return Pair{String,Matrix{Float64}}[names[i] => Float64[cols[i][rows[c][t]] for t in 1:niter, c in eachindex(ids)]
                                        for i in keep]
end

function _select(d::Draws, @nospecialize(variables))
    if variables !== nothing
        vs = variables isa Union{AbstractString,Symbol} ? (variables,) : variables
        names = first.(d)
        d = map(vs) do v
            k = findfirst(==(string(v)), names)
            k === nothing && throw(ArgumentError("no parameter called `$v`; the parameters are " *
                                                 join(first(names, 20), ", ") * (length(names) > 20 ? ", ..." : "")))
            d[k]
        end
        d = collect(Pair{String,Matrix{Float64}}, d)
    end
    isempty(d) && throw(ArgumentError("no parameters to plot"))
    return d
end

_chaincolor(c::Integer) = wong_colors()[mod1(c, length(wong_colors()))]

_setdefault!(ax::Axis, name::Symbol, s::String) = (getfield(ax, name) == "" && setproperty!(ax, name, s); ax)

_figure(size, @nospecialize(figure)) = Figure(; merge((; size), figure)...)

# --- draws: traces, densities, intervals --------------------------------------------

"""
    traceplot(draws; variables=nothing, density=true, figure=(;)) -> Figure

Trace plots: one row per parameter, with each chain's draws against
iteration on the left and, when `density = true`, each chain's density on
the right. `draws` is anything [`todraws`](@ref) reads, such as a chain or a
`NamedTuple` of iterations × chains matrices. `variables` picks parameters
by name, in order. `figure` passes keywords to [`Figure`](@ref).
"""
function traceplot(x; variables=nothing, density::Bool=true, figure=NamedTuple())
    @nospecialize
    return _traceplot(_select(todraws(x), variables), density, figure)
end

function _traceplot(d::Draws, density::Bool, @nospecialize(figure))
    nv = length(d)
    fig = _figure((density ? 800 : 600, max(220, 40 + 150nv)), figure)
    for (k, (name, m)) in enumerate(d)
        last = k == nv
        ax = Axis(fig[k, 1]; ylabel=name, xlabel=last ? "iteration" : "")
        for c in axes(m, 2)
            lines!(ax, view(m, :, c); color=(_chaincolor(c), 0.7), linewidth=0.7)
        end
        density || continue
        ax2 = Axis(fig[k, 2]; xlabel=last ? "value" : "")
        for c in axes(m, 2)
            density!(ax2, view(m, :, c); color=_chaincolor(c))
        end
    end
    density && colsize!(fig, 1, Relative(0.7))
    return fig
end

"""
    densities(draws; variables=nothing, combine=false, ncols=min(3, nparams), figure=(;)) -> Figure

Posterior densities, one panel per parameter, with each chain drawn
separately or, when `combine = true`, all chains pooled. `draws` is
anything [`todraws`](@ref) reads; `variables` picks parameters by name.
"""
function densities(x; variables=nothing, combine::Bool=false, ncols=nothing, figure=NamedTuple())
    @nospecialize
    d = _select(todraws(x), variables)
    return _densities(d, combine, ncols === nothing ? min(3, length(d)) : Int(ncols), figure)
end

function _densities(d::Draws, combine::Bool, nc::Int, @nospecialize(figure))
    nr = cld(length(d), nc)
    fig = _figure((40 + 260nc, 20 + 200nr), figure)
    for (k, (name, m)) in enumerate(d)
        ax = Axis(fig[cld(k, nc), mod1(k, nc)]; xlabel=name)
        if combine
            density!(ax, vec(m); color=_chaincolor(1))
        else
            for c in axes(m, 2)
                density!(ax, view(m, :, c); color=_chaincolor(c))
            end
        end
    end
    return fig
end

"""
    intervals(draws; variables=nothing, prob=0.5, prob_outer=0.9, point=median,
              color=:steelblue, figure=(;), axis=(;)) -> Figure
    intervals!(ax, draws; ...)

Posterior intervals, one row per parameter from the top down, as bayesplot's
`mcmc_intervals`: a thick line over the central `prob` interval, a thin line
over the central `prob_outer` interval and a marker at the `point`
estimate, a function of the draws such as `median` (the default) or `mean`.
The chains are pooled. `draws` is anything [`todraws`](@ref) reads.
"""
function intervals end

"""
    intervals!(ax, draws; variables=nothing, prob=0.5, prob_outer=0.9, point=median, color=:steelblue) -> ax

Draw [`intervals`](@ref) into the axis `ax`.
"""
function intervals!(ax::Axis, x; variables=nothing, prob=0.5, prob_outer=0.9, point=median, color=:steelblue)
    @nospecialize
    d = _select(todraws(x), variables)
    return _intervals!(ax, d, Float64(prob), Float64(prob_outer), point, color)
end

function intervals(x; variables=nothing, figure=NamedTuple(), axis=NamedTuple(), kwargs...)
    @nospecialize
    d = _select(todraws(x), variables)
    fig = _figure((500, 80 + 32 * length(d)), figure)
    ax = Axis(fig[1, 1]; merge((; ygridvisible=false), axis)...)
    intervals!(ax, d; kwargs...)
    return fig
end

function _intervals!(ax::Axis, d::Draws, prob::Float64, outer::Float64, @nospecialize(point), @nospecialize(color))
    (0 < prob < 1 && 0 < outer < 1) || throw(ArgumentError("prob and prob_outer must be between 0 and 1"))
    names = reverse!(first.(d))          # categories run upwards, so reverse to list from the top
    vals = [vec(m) for m in reverse(last.(d))]
    q(p) = [_quantile(v, p) for v in vals]
    a, b = (1 - prob) / 2, (1 - outer) / 2
    rangebars!(ax, names, q(b), q(1 - b); direction=:x, color, linewidth=1.5)
    rangebars!(ax, names, q(a), q(1 - a); direction=:x, color, linewidth=5)
    scatter!(ax, Float64[point(v) for v in vals], names; color=:white, strokecolor=color, strokewidth=2,
             markersize=9)
    return ax
end

# --- posterior predictive checks ------------------------------------------------------

"""
    ppcheck(y, yrep; type=:dens_overlay, stat=mean, figure=(;), axis=(;)) -> Figure
    ppcheck!(ax, y, yrep; type=:dens_overlay, stat=mean)

Posterior predictive check of the observed data `y` (a vector) against
replicated data sets `yrep`, one per row (draws × observations), as
bayesplot's `ppc_*` plots. `type` is

- `:dens_overlay`: the density of `y` over the density of each row of `yrep`;
- `:ecdf_overlay`: the same with empirical CDFs;
- `:hist`: histograms of `y` and of all of `yrep` pooled;
- `:stat`: a histogram of the statistic `stat` of each row of `yrep`, with
  `stat(y)` marked;
- `:bars`: for discrete data, bars counting each value in `y`, with the
  median and 90% interval of the counts in `yrep`.

The overlays draw a line per row, so pass a subset of the draws (say 50)
for them, and all of them for `:stat`.
"""
function ppcheck end

"""
    ppcheck!(ax, y, yrep; type=:dens_overlay, stat=mean) -> ax

Draw a posterior predictive check, as [`ppcheck`](@ref), into the axis `ax`.
"""
function ppcheck!(ax::Axis, y, yrep; type::Symbol=:dens_overlay, stat=mean)
    @nospecialize
    yv = _vec(y)
    R = Matrix{Float64}(yrep)
    size(R, 2) == length(yv) ||
        throw(DimensionMismatch("yrep needs one column per observation ($(length(yv))); got $(size(R, 2)) columns"))
    return _ppcheck!(ax, yv, R, type, stat)
end

function ppcheck(y, yrep; type::Symbol=:dens_overlay, stat=mean, figure=NamedTuple(), axis=NamedTuple())
    @nospecialize
    fig = _figure((600, 400), figure)
    ax = Axis(fig[1, 1]; merge((; xlabel=type === :stat ? "" : "y"), axis)...)
    ppcheck!(ax, y, yrep; type, stat)
    return fig
end

_statname(@nospecialize(f)) = f isa Function ? string(nameof(f)) : string(f)

function _ppcheck!(ax::Axis, y::Vector{Float64}, R::Matrix{Float64}, type::Symbol, @nospecialize(stat))
    if type === :dens_overlay
        for s in axes(R, 1)
            density!(ax, view(R, s, :); color=REPCOLOR, linewidth=0.8, label=s == 1 ? "y_rep" : "")
        end
        density!(ax, y; color=YCOLOR, linewidth=2.5, label="y")
        _setdefault!(ax, :ylabel, "density")
        axislegend(ax)
    elseif type === :ecdf_overlay
        for s in axes(R, 1)
            ecdfplot!(ax, view(R, s, :); color=REPCOLOR, label=s == 1 ? "y_rep" : "")
        end
        ecdfplot!(ax, y; color=YCOLOR, linewidth=2.5, label="y")
        _setdefault!(ax, :ylabel, "ECDF")
        axislegend(ax; position=:rb)
    elseif type === :hist
        lo, hi = min(minimum(y), minimum(R)), max(maximum(y), maximum(R))
        lo == hi && (lo -= 0.5; hi += 0.5)
        edges = collect(range(lo, hi; length=41))
        hist!(ax, vec(R); bins=edges, normalization=:pdf, color=(:steelblue, 0.5), label="y_rep")
        hist!(ax, y; bins=edges, normalization=:pdf, color=:transparent, strokecolor=YCOLOR, strokewidth=1.5,
              label="y")
        _setdefault!(ax, :ylabel, "density")
        axislegend(ax)
    elseif type === :stat
        t = Float64[stat(view(R, s, :)) for s in axes(R, 1)]
        hist!(ax, t; bins=30, color=(:steelblue, 0.6), label="T(y_rep)")
        vlines!(ax, Float64(stat(y)); color=YCOLOR, linewidth=3, label="T(y)")
        _setdefault!(ax, :xlabel, "T = " * _statname(stat))
        axislegend(ax)
    elseif type === :bars
        ks = sort!(unique(vcat(y, vec(R))))
        obs = [count(==(k), y) for k in ks]
        reps = [[count(==(k), view(R, s, :)) for s in axes(R, 1)] for k in ks]
        barplot!(ax, ks, obs; color=(:steelblue, 0.6), label="y")
        rangebars!(ax, ks, [_quantile(r, 0.05) for r in reps], [_quantile(r, 0.95) for r in reps];
                   color=YCOLOR, linewidth=2)
        scatter!(ax, ks, [median(r) for r in reps]; color=YCOLOR, label="y_rep")
        _setdefault!(ax, :ylabel, "count")
        axislegend(ax)
    else
        throw(ArgumentError("type must be :dens_overlay, :ecdf_overlay, :hist, :stat or :bars; got $(repr(type))"))
    end
    return ax
end
