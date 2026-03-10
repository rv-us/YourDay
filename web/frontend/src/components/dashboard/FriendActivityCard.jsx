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
    <div className="list">
      <div className="list-item">
        <div className="list-item__copy">
          <div className="list-item__title">{card.displayName}</div>
          <div className="list-item__meta">
            {card.isStale ? "Waiting for sync" : muted ? "Quiet yesterday" : "Active yesterday"}
          </div>
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
    </div>
  );
}
