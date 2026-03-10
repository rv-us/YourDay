import LeaderboardRow from "./LeaderboardRow";

export default function LeaderboardTable({ entries, currentUid }) {
  if (!entries.length) {
    return <p style={{ color: "#5A7A3A", padding: 20 }}>No entries yet.</p>;
  }

  return (
    <table style={{ width: "100%", borderCollapse: "collapse" }}>
      <thead>
        <tr style={{ borderBottom: "2px solid #C8DDB0" }}>
          {["Rank", "Player", "Level", "Garden Value"].map((h) => (
            <th
              key={h}
              style={{
                padding: "8px 14px",
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
  );
}
