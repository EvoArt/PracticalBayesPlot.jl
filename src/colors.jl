# Colours are stored as a CSS colour string plus an opacity. SVG understands
# CSS colour names, so Makie-style symbols (:steelblue, :black) pass through;
# the TikZ backend and colour mixing resolve them with the table below.

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
const BLACK = Paint("#000", 1.0)

isvisible(p::Paint) = p.alpha > 0 && p.css != "none"

# X11 greys (`:gray55`, as Makie accepts) are not CSS: store them as hex
function _grey(s::String)
    m = match(r"^gr[ae]y(\d{1,3})$", s)
    m === nothing && return s
    k = parse(Int, m.captures[1])
    k <= 100 || return s
    return _hex(round(Int, 2.55k), round(Int, 2.55k), round(Int, 2.55k))
end

_hex(r::Int, g::Int, b::Int) = string('#', string(r; base=16, pad=2), string(g; base=16, pad=2), string(b; base=16, pad=2))

paint(c::Paint, a::Real) = Paint(c.css, c.alpha * a)
paint(c::Symbol, a::Real) = paint(String(c), a)
function paint(c::AbstractString, a::Real)
    s = String(c)
    (s == "none" || s == "transparent") && return NOPAINT
    return Paint(_grey(s), Float64(a))
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

# --- resolving to RGB ------------------------------------------------------------------

# CSS colour names (the SVG/CSS set, which is what browsers draw)
const CSS_NAMES = let
    s = """
    aliceblue F0F8FF antiquewhite FAEBD7 aqua 00FFFF aquamarine 7FFFD4 azure F0FFFF beige F5F5DC
    bisque FFE4C4 black 000000 blanchedalmond FFEBCD blue 0000FF blueviolet 8A2BE2 brown A52A2A
    burlywood DEB887 cadetblue 5F9EA0 chartreuse 7FFF00 chocolate D2691E coral FF7F50
    cornflowerblue 6495ED cornsilk FFF8DC crimson DC143C cyan 00FFFF darkblue 00008B darkcyan 008B8B
    darkgoldenrod B8860B darkgray A9A9A9 darkgreen 006400 darkgrey A9A9A9 darkkhaki BDB76B
    darkmagenta 8B008B darkolivegreen 556B2F darkorange FF8C00 darkorchid 9932CC darkred 8B0000
    darksalmon E9967A darkseagreen 8FBC8F darkslateblue 483D8B darkslategray 2F4F4F
    darkslategrey 2F4F4F darkturquoise 00CED1 darkviolet 9400D3 deeppink FF1493 deepskyblue 00BFFF
    dimgray 696969 dimgrey 696969 dodgerblue 1E90FF firebrick B22222 floralwhite FFFAF0
    forestgreen 228B22 fuchsia FF00FF gainsboro DCDCDC ghostwhite F8F8FF gold FFD700
    goldenrod DAA520 gray 808080 grey 808080 green 008000 greenyellow ADFF2F honeydew F0FFF0
    hotpink FF69B4 indianred CD5C5C indigo 4B0082 ivory FFFFF0 khaki F0E68C lavender E6E6FA
    lavenderblush FFF0F5 lawngreen 7CFC00 lemonchiffon FFFACD lightblue ADD8E6 lightcoral F08080
    lightcyan E0FFFF lightgoldenrodyellow FAFAD2 lightgray D3D3D3 lightgreen 90EE90
    lightgrey D3D3D3 lightpink FFB6C1 lightsalmon FFA07A lightseagreen 20B2AA lightskyblue 87CEFA
    lightslategray 778899 lightslategrey 778899 lightsteelblue B0C4DE lightyellow FFFFE0
    lime 00FF00 limegreen 32CD32 linen FAF0E6 magenta FF00FF maroon 800000 mediumaquamarine 66CDAA
    mediumblue 0000CD mediumorchid BA55D3 mediumpurple 9370DB mediumseagreen 3CB371
    mediumslateblue 7B68EE mediumspringgreen 00FA9A mediumturquoise 48D1CC mediumvioletred C71585
    midnightblue 191970 mintcream F5FFFA mistyrose FFE4E1 moccasin FFE4B5 navajowhite FFDEAD
    navy 000080 oldlace FDF5E6 olive 808000 olivedrab 6B8E23 orange FFA500 orangered FF4500
    orchid DA70D6 palegoldenrod EEE8AA palegreen 98FB98 paleturquoise AFEEEE palevioletred DB7093
    papayawhip FFEFD5 peachpuff FFDAB9 peru CD853F pink FFC0CB plum DDA0DD powderblue B0E0E6
    purple 800080 rebeccapurple 663399 red FF0000 rosybrown BC8F8F royalblue 4169E1
    saddlebrown 8B4513 salmon FA8072 sandybrown F4A460 seagreen 2E8B57 seashell FFF5EE
    sienna A0522D silver C0C0C0 skyblue 87CEEB slateblue 6A5ACD slategray 708090
    slategrey 708090 snow FFFAFA springgreen 00FF7F steelblue 4682B4 tan D2B48C teal 008080
    thistle D8BFD8 tomato FF6347 turquoise 40E0D0 violet EE82EE wheat F5DEB3 white FFFFFF
    whitesmoke F5F5F5 yellow FFFF00 yellowgreen 9ACD32
    """
    w = split(s)
    Dict{String,UInt32}(String(w[i]) => parse(UInt32, w[i+1]; base=16) for i in 1:2:length(w))
end

_byte(s::AbstractString) = parse(Int, s; base=16)

# (r, g, b) in 0-255 for a stored CSS colour, or `nothing` if it is not one we know
function _rgb255(css::String)::Union{Nothing,NTuple{3,Int}}
    if startswith(css, '#')
        h = css[2:end]
        all(c -> isxdigit(c), h) || return nothing
        length(h) == 3 && return (17 * _byte(h[1:1]), 17 * _byte(h[2:2]), 17 * _byte(h[3:3]))
        length(h) == 6 && return (_byte(h[1:2]), _byte(h[3:4]), _byte(h[5:6]))
        return nothing
    elseif startswith(css, "rgb(") && endswith(css, ')')
        v = tryparse.(Int, split(css[5:end-1], ','))
        (length(v) == 3 && !any(isnothing, v)) || return nothing
        return (v[1], v[2], v[3])
    end
    u = get(CSS_NAMES, lowercase(css), nothing)
    u === nothing && return nothing
    return (Int(u >> 16), Int((u >> 8) & 0xff), Int(u & 0xff))
end

"""
    rgba(color) -> (r, g, b, alpha)

The colour as red, green, blue and opacity in 0-1, for any colour the
plotting functions accept (`:steelblue`, `"#0072B2"`, `(:red, 0.5)`, an
integer palette index, ...). Useful for mixing colours yourself.
"""
function rgba(@nospecialize(c))
    p = paint(c, 1.0)
    isvisible(p) || return (0.0, 0.0, 0.0, 0.0)
    v = _rgb255(p.css)
    v === nothing && throw(ArgumentError("unknown colour name $(repr(p.css))"))
    return (v[1] / 255, v[2] / 255, v[3] / 255, p.alpha)
end

# --- colour maps ----------------------------------------------------------------------

const COLORMAPS = Dict{Symbol,Vector{String}}(
    :viridis => ["#440154", "#482878", "#3E4A89", "#31688E", "#26828E", "#1F9E89", "#35B779", "#6DCD59", "#FDE725"],
    :cividis => ["#00204D", "#00336F", "#39486B", "#575C6D", "#707173", "#8A8779", "#A69D75", "#C4B56C", "#E4CF5B", "#FFEA46"],
    :grays => ["#000000", "#FFFFFF"],
    :blues => ["#F7FBFF", "#DEEBF7", "#C6DBEF", "#9ECAE1", "#6BAED6", "#4292C6", "#2171B5", "#08519C", "#08306B"],
    :reds => ["#FFF5F0", "#FEE0D2", "#FCBBA1", "#FC9272", "#FB6A4A", "#EF3B2C", "#CB181D", "#A50F15", "#67000D"],
)

function _stops(@nospecialize(cmap))::Vector{NTuple{3,Float64}}
    cs = if cmap isa Symbol
        haskey(COLORMAPS, cmap) ||
            throw(ArgumentError("colormap must be one of $(join(sort!(collect(keys(COLORMAPS))), ", ")) or a vector of colours; got :$cmap"))
        COLORMAPS[cmap]
    else
        collect(cmap)
    end
    length(cs) >= 2 || throw(ArgumentError("a colormap needs at least two colours"))
    return [(r = rgba(c); (r[1], r[2], r[3])) for c in cs]
end

# colour at t ∈ [0, 1] along the stops
function _cmap(stops::Vector{NTuple{3,Float64}}, t::Float64)
    isfinite(t) || return NOPAINT
    t = clamp(t, 0.0, 1.0)
    n = length(stops)
    u = t * (n - 1)
    i = min(floor(Int, u), n - 2)
    f = u - i
    a, b = stops[i+1], stops[i+2]
    return _rgb(a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), a[3] + f * (b[3] - a[3]), 1.0)
end
