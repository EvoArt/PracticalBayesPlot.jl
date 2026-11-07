# Tick positions ("nice numbers") and tick-label formatting.

# smallest number of decimals that represents `step` exactly (to 1e-9)
function _decimals(step::Float64)
    step == 0 && return 0
    for d in 0:12
        abs(round(step; digits=d) - step) <= 1e-9 * abs(step) && return d
    end
    return 12
end

# Steps of 1, 2, 2.5 or 5 times a power of ten, choosing the one whose tick
# count is closest to `target`. Returns (ticks, decimals for the labels).
function nice_ticks(lo::Float64, hi::Float64, target::Int)
    span = hi - lo
    (isfinite(span) && span > 0) || return Float64[], 0
    mag = 10.0^floor(log10(span / max(target, 1)))
    best = mag
    bestscore = Inf
    for m in (1.0, 2.0, 2.5, 5.0, 10.0)
        step = m * mag
        n = floor(hi / step + 1e-9) - ceil(lo / step - 1e-9) + 1
        score = (n < target ? 2 * (target - n) : n - target) + (m == 2.5 ? 2.5 : 0.0)
        if n >= 2 && score < bestscore
            best, bestscore = step, score
        end
    end
    k1 = ceil(lo / best - 1e-9)
    k2 = floor(hi / best + 1e-9)
    return Float64[k * best for k in k1:k2], _decimals(best)
end

const MINUS = '−'

function fmt_tick(x::Float64, d::Int)
    if iszero(x)
        return d == 0 ? "0" : "0." * "0"^d
    end
    a = abs(x)
    s = if a >= 1e6 || a < 1e-4
        e = floor(Int, log10(a))
        m = round(a / 10.0^e; digits=2)
        ms = string(m)
        endswith(ms, ".0") && (ms = ms[1:end-2])
        string(ms, "e", e)
    elseif d == 0
        string(round(Int, a))
    else
        t = string(round(a; digits=d))
        i = findfirst('.', t)
        if i === nothing
            t = t * "." * "0"^d
        else
            nf = lastindex(t) - i
            nf < d && (t *= "0"^(d - nf))
        end
        t
    end
    return x < 0 ? string(MINUS, s) : s
end

function _ticks(spec, categories::Vector{String}, lo::Float64, hi::Float64, target::Int)
    if spec === nothing || spec === :auto
        if !isempty(categories)
            pos = collect(1.0:length(categories))
            labels = copy(categories)
        else
            pos, d = nice_ticks(lo, hi, target)
            labels = [fmt_tick(v, d) for v in pos]
        end
    elseif spec isa Tuple && length(spec) == 2
        pos = Float64[Float64(v) for v in spec[1]]
        labels = String[string(v) for v in spec[2]]
        length(pos) == length(labels) ||
            throw(ArgumentError("ticks: $(length(pos)) positions but $(length(labels)) labels"))
    elseif spec isa AbstractVector
        pos = Float64[Float64(v) for v in spec]
        d = isempty(pos) ? 0 : min(maximum(_decimals, pos), 6)
        labels = [fmt_tick(v, d) for v in pos]
    else
        throw(ArgumentError("ticks must be nothing, a vector of positions, or (positions, labels); got $(repr(spec))"))
    end
    tol = 1e-9 * max(abs(lo), abs(hi), hi - lo)
    keep = findall(v -> lo - tol <= v <= hi + tol, pos)
    return pos[keep], labels[keep]
end
