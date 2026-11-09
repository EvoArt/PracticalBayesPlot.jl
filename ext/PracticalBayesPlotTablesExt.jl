module PracticalBayesPlotTablesExt

# Draws from any Tables.jl table, such as a DataFrame: every numeric column is
# a parameter, split into chains by a `chain` column if there is one.

using PracticalBayesPlot
using Tables

function PracticalBayesPlot._table_draws(x)
    Tables.istable(x) || throw(ArgumentError("cannot read posterior draws from a $(typeof(x)); see " *
                                             "`PracticalBayesPlot.todraws` for what can be read"))
    cols = Tables.columns(x)
    names = Tables.columnnames(cols)
    return PracticalBayesPlot._column_draws(String[string(n) for n in names],
                                            Any[Tables.getcolumn(cols, n) for n in names])
end

end
