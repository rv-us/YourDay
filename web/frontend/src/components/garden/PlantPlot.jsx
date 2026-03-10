import { useState } from "react";
import { theme } from "../../styles/theme";
import { resolvePlantAssetName } from "../../lib/plantCatalog";

function getCurrentSeason() {
  const month = new Date().getMonth() + 1;
  if (month >= 3 && month <= 5) return "Spring";
  if (month >= 6 && month <= 8) return "Summer";
  if (month >= 9 && month <= 11) return "Fall";
  return "Winter";
}

function getGrowthImageSrc(plant) {
  if (plant.daysLeftTillFullyGrown <= 0) {
    const assetName = resolvePlantAssetName(plant);
    return assetName ? `/plants/${assetName}.png` : null;
  }
  if (plant.initialDaysToGrow > 0 && plant.daysLeftTillFullyGrown <= plant.initialDaysToGrow / 2) {
    return "/plants/seedling.png";
  }
  return "/plants/seed.png";
}

export default function PlantPlot({ plant, onClick }) {
  const [imgError, setImgError] = useState(false);
  const rarityColor = theme.colors.rarity[plant.rarity] || "#9E9E9E";
  const isGrown = plant.daysLeftTillFullyGrown <= 0;
  const season = getCurrentSeason();
  const hasBonus = isGrown && plant.theme === season;
  const imgSrc = getGrowthImageSrc(plant);

  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        width: "100%",
        height: "100%",
        border: 0,
        padding: 0,
        background: "transparent",
        cursor: "pointer",
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          position: "relative",
          display: "grid",
          placeItems: "center",
          transition: "transform 0.15s ease",
        }}
        onMouseEnter={(event) => {
          event.currentTarget.style.transform = "translateY(-2px) scale(1.04)";
        }}
        onMouseLeave={(event) => {
          event.currentTarget.style.transform = "translateY(0) scale(1)";
        }}
      >
        {!imgError && imgSrc ? (
          <img
            src={imgSrc}
            alt={plant.name}
            onError={() => setImgError(true)}
            style={{
              width: isGrown ? "92%" : "58%",
              height: isGrown ? "92%" : "58%",
              objectFit: "contain",
              filter: `drop-shadow(0 10px 16px ${rarityColor}44)`,
            }}
          />
        ) : (
          <div
            style={{
              width: "72%",
              height: "72%",
              background: `${rarityColor}44`,
              borderRadius: 12,
              display: "grid",
              placeItems: "center",
              fontSize: 12,
              color: rarityColor,
              fontWeight: 700,
              textAlign: "center",
              padding: 4,
            }}
          >
            {plant.name.slice(0, 2)}
          </div>
        )}

        <div
          style={{
            position: "absolute",
            bottom: "-6%",
            left: "50%",
            transform: "translateX(-50%)",
            textAlign: "center",
            fontSize: 9,
            fontWeight: 700,
            color: isGrown ? "#2E6B10" : "#BF360C",
            background: isGrown ? "rgba(200, 230, 201, 0.95)" : "rgba(251, 233, 231, 0.95)",
            borderRadius: 999,
            padding: "2px 6px",
            whiteSpace: "nowrap",
          }}
        >
          {isGrown ? (hasBonus ? "Season Bonus" : "Grown") : `${plant.daysLeftTillFullyGrown}d left`}
        </div>
      </div>
    </button>
  );
}
