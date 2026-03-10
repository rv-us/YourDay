import { theme } from "../../styles/theme";

export default function RarityBadge({ rarity }) {
  const color = theme.colors.rarity[rarity] || "#9E9E9E";
  return (
    <span
      style={{
        display: "inline-block",
        padding: "2px 8px",
        borderRadius: 12,
        fontSize: 11,
        fontWeight: 700,
        color,
        background: color + "22",
        border: `1px solid ${color}55`,
      }}
    >
      {rarity}
    </span>
  );
}
