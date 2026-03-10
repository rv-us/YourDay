import { Card, CardContent } from "../ui/card";

export default function FriendActivityCard({ card }) {
  const muted = card.isNoActivityYesterday;

  const stats = [
    { label: "Points", value: Math.round(card.yesterdayPoints || 0) },
    { label: "Streak", value: card.taskStreak || 0 },
    {
      label: "Tasks",
      value:
        card.totalTasksYesterday > 0
          ? `${card.completedTasksYesterday}/${card.totalTasksYesterday}`
          : `${card.completedTasksYesterday || 0}`,
    },
  ];

  return (
    <Card variant={muted ? "muted" : undefined}>
      <CardContent>
        <div className="stack--sm">
          <div style={{ display: "flex", justifyContent: "space-between", gap: "0.75rem", alignItems: "center" }}>
            <div className="stack--sm" style={{ gap: "0.18rem" }}>
              <span className="eyebrow">Friend snapshot</span>
              <div className="list-item__title">{card.displayName}</div>
            </div>
            <span className={`status-pill${muted ? "" : " status-pill--warm"}`}>
              {muted ? "Quiet" : "Active"}
            </span>
          </div>

          <div className="card-grid card-grid--three">
            {stats.map((stat) => (
              <div key={stat.label} className="metric-card metric-card--light">
                <div className="metric-label">{stat.label}</div>
                <div className="metric-value" style={{ fontSize: "1.3rem", color: "var(--moss-700)" }}>
                  {stat.value}
                </div>
              </div>
            ))}
          </div>

          <div className="list-item__meta">
            {card.isStale
              ? "Waiting for their next sync."
              : muted
                ? "No completed activity landed yesterday."
                : "Healthy momentum across the board."}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
