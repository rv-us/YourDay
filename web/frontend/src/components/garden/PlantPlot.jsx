import { useState } from "react";
import { theme } from "../../styles/theme";

function getCurrentSeason() {
  const month = new Date().getMonth() + 1;
  if (month >= 3 && month <= 5) return "Spring";
  if (month >= 6 && month <= 8) return "Summer";
  if (month >= 9 && month <= 11) return "Fall";
  return "Winter";
}

function getGrowthImageSrc(plant) {
  if (plant.daysLeftTillFullyGrown <= 0) return `/plants/${plant.assetName}.png`;
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
    <div
      onClick={onClick}
      style={{
        border: `2px solid ${rarityColor}`,
        borderRadius: 10,
        background: `${rarityColor}18`,
        cursor: "pointer",
        overflow: "hidden",
        position: "relative",
        aspectRatio: "1",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        transition: "transform 0.15s, box-shadow 0.15s",
      }}
      onMouseEnter={(event) => {
        event.currentTarget.style.transform = "scale(1.04)";
        event.currentTarget.style.boxShadow = `0 4px 12px ${rarityColor}44`;
      }}
      onMouseLeave={(event) => {
        event.currentTarget.style.transform = "scale(1)";
        event.currentTarget.style.boxShadow = "none";
      }}
    >
      {!imgError ? (
        <img
          src={imgSrc}
          alt={plant.name}
          onError={() => setImgError(true)}
          style={{ width: "80%", height: "80%", objectFit: "contain" }}
        />
      ) : (
        <div
          style={{
            width: "80%",
            height: "80%",
            background: `${rarityColor}44`,
            borderRadius: 6,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 11,
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
          bottom: 2,
          left: 2,
          right: 2,
          textAlign: "center",
          fontSize: 9,
          fontWeight: 700,
          color: isGrown ? "#2E6B10" : "#BF360C",
          background: isGrown ? "#C8E6C9" : "#FBE9E7",
          borderRadius: 4,
          padding: "1px 2px",
        }}
      >
        {isGrown ? (hasBonus ? "Season Bonus" : "Grown") : `${plant.daysLeftTillFullyGrown}d left`}
      </div>
    </div>
  );
}
