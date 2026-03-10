export default function StatBadge({ label, value, color = "var(--moss-600)" }) {
  return (
    <div className="ui-card ui-card--muted">
      <div className="ui-card__content">
        <div className="mini-stat">
          <span className="metric-label">{label}</span>
          <span className="mini-stat__value" style={{ color }}>
            {value}
          </span>
        </div>
      </div>
    </div>
  );
}
