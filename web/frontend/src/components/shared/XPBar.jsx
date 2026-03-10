export default function XPBar({ currentXP, xpToNext, level }) {
  const pct = xpToNext > 0 ? Math.min((currentXP / xpToNext) * 100, 100) : 100;

  return (
    <div className="stack--sm" style={{ gap: "0.5rem" }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: "0.75rem", flexWrap: "wrap" }}>
        <span className="eyebrow">Level {level}</span>
        <span className="list-item__meta" style={{ color: "rgba(247,244,234,0.82)" }}>
          {Math.round(currentXP)} / {Math.round(xpToNext)} XP
        </span>
      </div>
      <div
        className="progress"
        style={{ background: "rgba(255,255,255,0.18)", boxShadow: "inset 0 1px 0 rgba(255,255,255,0.08)" }}
      >
        <div
          className="progress__fill"
          style={{ width: `${pct}%`, background: "linear-gradient(90deg, #d7eba5, #f1cd76 85%)" }}
        />
      </div>
    </div>
  );
}
