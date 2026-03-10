import LeaderboardRow from "./LeaderboardRow";

export default function LeaderboardTable({ entries, currentUid }) {
  if (!entries.length) {
    return <div className="empty-state">No entries yet.</div>;
  }

  return (
    <div className="table-shell">
      <table className="data-table">
        <thead>
          <tr>
          {["Rank", "Player", "Level", "Garden Value"].map((h) => (
            <th
              key={h}
              style={{
                textAlign: h === "Garden Value" ? "right" : h === "Level" ? "center" : "left",
                fontSize: 12,
                color: "#5A7A3A",
                fontWeight: 600,
                textTransform: "uppercase",
                letterSpacing: 0.5,
              }}
            >
              {h}
            </th>
          ))}
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <LeaderboardRow
              key={entry.id}
              entry={entry}
              isCurrentUser={entry.id === currentUid}
            />
          ))}
        </tbody>
      </table>
    </div>
  );
}
