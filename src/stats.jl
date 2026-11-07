# Small statistics helpers, kept here so the package needs no Statistics import.

# quantile of sorted data, R's type 7 (the Statistics.quantile default)
function _quantile_sorted(s::Vector{Float64}, p::Float64)
    n = length(s)
    n == 1 && return s[1]
    h = (n - 1) * p + 1
    lo = floor(Int, h)
    lo >= n && return s[n]
    return s[lo] + (h - lo) * (s[lo+1] - s[lo])
end

# Silverman's rule of thumb
function bandwidth(x::Vector{Float64})
    n = length(x)
    s = sort(x)
    m = sum(s) / n
    sd = n > 1 ? sqrt(sum(v -> (v - m)^2, s) / (n - 1)) : 0.0
    iqr = _quantile_sorted(s, 0.75) - _quantile_sorted(s, 0.25)
    h = 0.9 * min(sd, iqr / 1.34) * n^(-1 / 5)
    h > 0 && return h
    return (sd > 0 ? sd : 1.0) * n^(-1 / 5)
end

"""
    PracticalBayesPlot.kde(x, grid, h=bandwidth(x))

Gaussian kernel density estimate of the data `x` at the points `grid`, with
bandwidth `h` (Silverman's rule by default).
"""
function kde(x::Vector{Float64}, grid::Vector{Float64}, h::Float64=bandwidth(x))
    n = length(x)
    c = 1 / (n * h * sqrt(2π))
    out = Vector{Float64}(undef, length(grid))
    @inbounds for (k, g) in enumerate(grid)
        acc = 0.0
        for v in x
            z = (g - v) / h
            acc += exp(-z * z / 2)
        end
        out[k] = c * acc
    end
    return out
end
kde(x, grid, h=nothing) = (xv = _f64(x); kde(xv, _f64(grid), h === nothing ? bandwidth(xv) : Float64(h)))

function _edges(v::Vector{Float64}, bins::Integer)
    bins >= 1 || throw(ArgumentError("bins must be at least 1"))
    lo, hi = extrema(v)
    if lo == hi
        lo -= 0.5
        hi += 0.5
    end
    return collect(range(lo, hi; length=bins + 1))
end
function _edges(::Vector{Float64}, bins::AbstractVector)
    e = sort!(_f64(bins))
    length(e) >= 2 || throw(ArgumentError("bin edges need at least two values"))
    return e
end

function _bincounts(v::Vector{Float64}, edges::Vector{Float64})
    nb = length(edges) - 1
    c = zeros(nb)
    for x in v
        i = searchsortedlast(edges, x)
        i == nb + 1 && x == edges[end] && (i = nb)   # right edge belongs to the last bin
        1 <= i <= nb && (c[i] += 1)
    end
    return c
end
