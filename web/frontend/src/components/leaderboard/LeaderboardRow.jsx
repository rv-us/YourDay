export default function LeaderboardRow({ entry, isCurrentUser }) {
  return (
    <tr
      style={{
        background: isCurrentUser ? "#E8F5E9" : "transparent",
        fontWeight: isCurrentUser ? 700 : 400,
      }}
    >
      <td style={{ padding: "10px 14px", fontSize: 14, color: "#5A7A3A" }}>
        {entry.rank === 1 ? "🥇" : entry.rank === 2 ? "🥈" : entry.rank === 3 ? "🥉" : `#${entry.rank}`}
      </td>
      <td style={{ padding: "10px 14px", fontSize: 14 }}>
        {entry.displayName}
        {isCurrentUser && <span style={{ marginLeft: 6, fontSize: 11, color: "#56AB2F" }}>(you)</span>}
      </td>
      <td style={{ padding: "10px 14px", fontSize: 14, textAlign: "center" }}>
        Lv. {entry.playerLevel}
      </td>
      <td style={{ padding: "10px 14px", fontSize: 14, textAlign: "right" }}>
        {Math.round(entry.gardenValue)} pts
      </td>
    </tr>
  );
}
