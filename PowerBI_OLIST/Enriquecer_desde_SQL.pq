// Consulta opcional; no ejecutada. Usar permiso SELECT exclusivamente.
let
    Base = Sql.Database("JUAN", "OLIST_DW", [CreateNavigationProperties=false]),
    Features = Base{[Schema="gold", Item="order_anomaly_features"]}[Data],
    Resultado = Table.NestedJoin(Scoring, {"order_id"}, Features, {"order_id"}, "Características", JoinKind.LeftOuter)
in
    Resultado
