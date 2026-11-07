# Colours are stored as a CSS colour string plus an opacity. SVG understands
# CSS colour names, so Makie-style symbols (:steelblue, :black) pass through.

const WONG = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#F0E442"]

"""
    wong_colors()

The default colour cycle, Wong's colour-blind-safe palette in the same order
as Makie's, as hex strings. An integer colour `k` picks the `k`th entry.
"""
wong_colors() = copy(WONG)

struct Paint
    css::String
    alpha::Float64
end

const NOPAINT = Paint("none", 0.0)

isvisible(p::Paint) = p.alpha > 0 && p.css != "none"

paint(c::Paint, a::Real) = Paint(c.css, c.alpha * a)
paint(c::Symbol, a::Real) = paint(String(c), a)
function paint(c::AbstractString, a::Real)
    s = String(c)
    (s == "none" || s == "transparent") && return NOPAINT
    return Paint(s, Float64(a))
end
paint(c::Integer, a::Real) = Paint(WONG[mod1(c, length(WONG))], Float64(a))
paint(c::Tuple{Any,Real}, a::Real) = paint(c[1], a * c[2])
paint(c::NTuple{3,Real}, a::Real) = _rgb(c[1], c[2], c[3], a)
function paint(c, a::Real)
    # duck-typed support for colour objects with r, g, b (and alpha) fields,
    # such as Colors.jl's RGB and RGBA
    if hasproperty(c, :r) && hasproperty(c, :g) && hasproperty(c, :b)
        al = hasproperty(c, :alpha) ? Float64(getproperty(c, :alpha)) : 1.0
        return _rgb(c.r, c.g, c.b, a * al)
    end
    throw(ArgumentError("unsupported colour $(repr(c)): use a name (:steelblue or \"red\"), " *
                        "a hex string, an (r, g, b) tuple with values in 0-1, an integer " *
                        "palette index, or a (colour, alpha) tuple"))
end

function _rgb(r, g, b, a)
    q(v) = round(Int, 255 * clamp(Float64(v), 0.0, 1.0))
    return Paint(string("rgb(", q(r), ",", q(g), ",", q(b), ")"), Float64(a))
end
