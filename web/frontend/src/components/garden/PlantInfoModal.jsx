import { useState } from "react";
import RarityBadge from "../shared/RarityBadge";
import { theme } from "../../styles/theme";

function getCurrentSeason() {
  const m = new Date().getMonth() + 1;
  if (m >= 3 && m <= 5) return "Spring";
  if (m >= 6 && m <= 8) return "Summer";
  if (m >= 9 && m <= 11) return "Fall";
  return "Winter";
}

function getDynamicValue(plant) {
  if (plant.daysLeftTillFullyGrown > 0) return 0;
  const season = getCurrentSeason();
  return Math.round(plant.baseValue * (plant.theme === season ? 1.5 : 1));
}

export default function PlantInfoModal({ plant, onClose }) {
  const [imgError, setImgError] = useState(false);
  const rarityColor = theme.colors.rarity[plant.rarity] || "#9E9E9E";
  const season = getCurrentSeason();
  const hasBonus = plant.daysLeftTillFullyGrown <= 0 && plant.theme === season;
  const dynamicValue = getDynamicValue(plant);

  return (
    <div
      onClick={onClose}
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.5)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 1000,
        padding: 20,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "white",
          borderRadius: 20,
          padding: 24,
          maxWidth: 360,
          width: "100%",
          boxShadow: "0 8px 32px rgba(0,0,0,0.2)",
        }}
      >
        <div style={{ textAlign: "center", marginBottom: 16 }}>
          {!imgError ? (
            <img
              src={`/plants/${plant.assetName}.png`}
              alt={plant.name}
              onError={() => setImgError(true)}
              style={{ width: 100, height: 100, objectFit: "contain" }}
            />
          ) : (
            <div
              style={{
                width: 100,
                height: 100,
                margin: "0 auto",
                background: rarityColor + "44",
                borderRadius: 10,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: 24,
                fontWeight: 800,
                color: rarityColor,
              }}
            >
              {plant.name.slice(0, 2)}
            </div>
          )}
        </div>

        <h3 style={{ fontSize: 20, fontWeight: 800, marginBottom: 8, textAlign: "center" }}>
          {plant.name}
        </h3>

        <div style={{ display: "flex", gap: 8, justifyContent: "center", marginBottom: 16 }}>
          <RarityBadge rarity={plant.rarity} />
          <span
            style={{
              display: "inline-block",
              padding: "2px 8px",
              borderRadius: 12,
              fontSize: 11,
              fontWeight: 700,
              color: theme.colors.season[plant.theme] || "#555",
              background: (theme.colors.season[plant.theme] || "#555") + "22",
              border: `1px solid ${theme.colors.season[plant.theme] || "#555"}55`,
            }}
          >
            {plant.theme}
          </span>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 16 }}>
          {[
            { label: "Status", value: plant.daysLeftTillFullyGrown <= 0 ? "Fully Grown 🌸" : `${plant.daysLeftTillFullyGrown} days left` },
            { label: "Base Value", value: `${plant.baseValue} pts` },
            { label: "Current Value", value: `${dynamicValue} pts${hasBonus ? " ✨" : ""}` },
            { label: "Position", value: `(${plant.position?.x ?? "?"}, ${plant.position?.y ?? "?"})` },
          ].map(({ label, value }) => (
            <div key={label} style={{ background: "#F5F1E8", borderRadius: 8, padding: "8px 12px" }}>
              <div style={{ fontSize: 10, color: "#5A7A3A", marginBottom: 2 }}>{label}</div>
              <div style={{ fontSize: 13, fontWeight: 600 }}>{value}</div>
            </div>
          ))}
        </div>

        {hasBonus && (
          <div
            style={{
              background: "#FFF8E1",
              border: "1px solid #FFC107",
              borderRadius: 8,
              padding: "8px 12px",
              fontSize: 12,
              color: "#795548",
              textAlign: "center",
              marginBottom: 16,
            }}
          >
            ✨ {plant.theme} season bonus active! (+50% value)
          </div>
        )}

        <button className="btn btn-secondary" onClick={onClose} style={{ width: "100%" }}>
          Close
        </button>
      </div>
    </div>
  );
}
