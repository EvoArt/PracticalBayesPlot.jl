# API

```@meta
CurrentModule = PracticalBayesPlot
```

```@docs
PracticalBayesPlot
```

```@index
Pages = ["api.md"]
```

## Bayesian workflow plots

```@docs
traceplot
densities
intervals
intervals!
ppcheck
ppcheck!
todraws
```

## Figures and axes

```@docs
Figure
Axis
current_axis
colsize!
rowsize!
Relative
xlims!
ylims!
limits!
axislegend
```

## Plotting into an axis

```@docs
lines!
stairs!
scatter!
band!
barplot!
hist!
density!
ecdfplot!
rangebars!
hlines!
vlines!
text!
```

## One-call forms

Each makes a `Figure` with one `Axis` and draws into it. `figure = (; ...)`
and `axis = (; ...)` pass keywords to `Figure` and `Axis`.

```@docs
lines
stairs
scatter
band
barplot
hist
density
ecdfplot
rangebars
```

## Output

```@docs
svg
save
preview
```

## Colours and statistics

```@docs
wong_colors
kde
```
