import { useState } from "react";
import PlantPlot from "./PlantPlot";
import PlantInfoModal from "./PlantInfoModal";

const GRID_COLUMNS = 10;
const GRID_ROWS = 8;
const GRID_LEFT_FRACTION = 0.10;
const GRID_TOP_FRACTION = 0.19;
const GRID_WIDTH_FRACTION = 0.80;
const GRID_HEIGHT_FRACTION = 0.65;

const TILE_UNLOCK_ORDER = [
  { x: 4, y: 3 }, { x: 5, y: 3 }, { x: 4, y: 4 }, { x: 5, y: 4 }, { x: 3, y: 3 }, { x: 6, y: 3 },
  { x: 3, y: 4 }, { x: 6, y: 4 }, { x: 4, y: 2 }, { x: 5, y: 2 }, { x: 4, y: 5 }, { x: 5, y: 5 },
  { x: 3, y: 2 }, { x: 6, y: 2 }, { x: 3, y: 5 }, { x: 6, y: 5 }, { x: 2, y: 3 }, { x: 7, y: 3 },
  { x: 2, y: 4 }, { x: 7, y: 4 }, { x: 4, y: 1 }, { x: 5, y: 1 }, { x: 4, y: 6 }, { x: 5, y: 6 },
  { x: 2, y: 2 }, { x: 7, y: 2 }, { x: 1, y: 3 }, { x: 8, y: 3 }, { x: 3, y: 1 }, { x: 6, y: 1 },
  { x: 2, y: 5 }, { x: 7, y: 5 }, { x: 1, y: 2 }, { x: 8, y: 2 }, { x: 1, y: 4 }, { x: 9, y: 4 },
  { x: 0, y: 3 }, { x: 9, y: 3 }, { x: 2, y: 1 }, { x: 7, y: 1 }, { x: 1, y: 5 }, { x: 6, y: 6 },
  { x: 0, y: 2 },
];

function getPlotStyle(position) {
  const tileWidth = GRID_WIDTH_FRACTION / GRID_COLUMNS;
  const tileHeight = GRID_HEIGHT_FRACTION / GRID_ROWS;
  const centerX = GRID_LEFT_FRACTION + ((position.x + 0.5) * tileWidth);
  const centerY = GRID_TOP_FRACTION + ((position.y + 0.5) * tileHeight);

  return {
    left: `${centerX * 100}%`,
    top: `${(centerY + tileHeight * 1.9) * 100}%`,
    width: `${tileWidth * 1.55 * 100}%`,
    height: `${tileHeight * 2.35 * 100}%`,
    transform: "translate(-50%, -100%)",
  };
}

export default function GardenGrid({ placedPlants, numberOfOwnedPlots }) {
  const [selectedPlant, setSelectedPlant] = useState(null);
  const plantByPosition = new Map(
    placedPlants.map((plant) => [`${plant.position?.x ?? 0},${plant.position?.y ?? 0}`, plant])
  );

  const unlockedPlots = TILE_UNLOCK_ORDER.slice(0, numberOfOwnedPlots).map((position) => ({
    key: `${position.x},${position.y}`,
    position,
    plant: plantByPosition.get(`${position.x},${position.y}`) || null,
  }));

  return (
    <>
      <div style={{ position: "absolute", inset: 0, zIndex: 2, pointerEvents: "none" }}>
        {unlockedPlots.map(({ key, position, plant }) => (
          <div
            key={key}
            style={{
              position: "absolute",
              ...getPlotStyle(position),
              pointerEvents: "auto",
            }}
          >
            {plant ? (
              <PlantPlot plant={plant} onClick={() => setSelectedPlant(plant)} />
            ) : (
              <div
                style={{
                  width: "100%",
                  height: "100%",
                  border: "1.5px dashed rgba(200, 221, 176, 0.9)",
                  borderRadius: 16,
                  display: "grid",
                  placeItems: "center",
                  color: "rgba(200, 221, 176, 0.95)",
                  background: "rgba(255,255,255,0.12)",
                  backdropFilter: "blur(2px)",
                  fontSize: 18,
                  fontWeight: 700,
                }}
              >
                +
              </div>
            )}
          </div>
        ))}
      </div>

      {selectedPlant && (
        <PlantInfoModal plant={selectedPlant} onClose={() => setSelectedPlant(null)} />
      )}
    </>
  );
}
