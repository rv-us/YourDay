export default function LeaderboardRow({ entry, isCurrentUser }) {
  const rankLabel = entry.rank === 1 ? "🥇" : entry.rank === 2 ? "🥈" : entry.rank === 3 ? "🥉" : `#${entry.rank}`;

  return (
    <tr
      style={{
        background: isCurrentUser ? "rgba(103, 163, 71, 0.08)" : "transparent",
        fontWeight: isCurrentUser ? 700 : 400,
      }}
    >
      <td style={{ fontSize: 14, color: "#5A7A3A" }}>{rankLabel}</td>
      <td style={{ fontSize: 14 }}>
        {entry.displayName}
        {isCurrentUser && <span style={{ marginLeft: 6, fontSize: 11, color: "#56AB2F" }}>(you)</span>}
      </td>
      <td style={{ fontSize: 14, textAlign: "center" }}>Lv. {entry.playerLevel}</td>
      <td style={{ fontSize: 14, textAlign: "right" }}>{Math.round(entry.gardenValue)} pts</td>
    </tr>
  );
}
