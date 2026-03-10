import { useState } from "react";
import PlantPlot from "./PlantPlot";
import PlantInfoModal from "./PlantInfoModal";

export default function GardenGrid({ placedPlants, numberOfOwnedPlots }) {
  const [selectedPlant, setSelectedPlant] = useState(null);
  const cols = 3;
  const rows = Math.ceil(numberOfOwnedPlots / cols);

  // Build a lookup of position -> plant
  const plantByPosition = {};
  for (const plant of placedPlants) {
    const key = `${plant.position?.x ?? 0},${plant.position?.y ?? 0}`;
    plantByPosition[key] = plant;
  }

  const plots = [];
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const plotIndex = row * cols + col;
      if (plotIndex >= numberOfOwnedPlots) break;
      const key = `${col},${row}`;
      plots.push({ key, plant: plantByPosition[key] || null });
    }
  }

  return (
    <>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(${cols}, 1fr)`,
          gap: 10,
          maxWidth: 400,
        }}
      >
        {plots.map(({ key, plant }) =>
          plant ? (
            <PlantPlot
              key={key}
              plant={plant}
              onClick={() => setSelectedPlant(plant)}
            />
          ) : (
            <div
              key={key}
              style={{
                aspectRatio: "1",
                border: "2px dashed #C8DDB0",
                borderRadius: 10,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#C8DDB0",
                fontSize: 24,
              }}
            >
              +
            </div>
          )
        )}
      </div>

      {selectedPlant && (
        <PlantInfoModal plant={selectedPlant} onClose={() => setSelectedPlant(null)} />
      )}
    </>
  );
}
