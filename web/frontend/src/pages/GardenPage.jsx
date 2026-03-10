import { useEffect, useState } from "react";
import { getGarden } from "../api/gardenApi";
import GardenGrid from "../components/garden/GardenGrid";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";
import { getPlantDisplayName } from "../lib/plantCatalog";

function getCurrentSeason() {
  const month = new Date().getMonth() + 1;
  if (month >= 3 && month <= 5) return "Spring";
  if (month >= 6 && month <= 8) return "Summer";
  if (month >= 9 && month <= 11) return "Fall";
  return "Winter";
}

const SEASON_BG = {
  Spring: { island: "/garden/spring_main_island.png", gradient: "linear-gradient(180deg, #8fcf9a 0%, #dff1d4 100%)" },
  Summer: { island: "/garden/summer_main_island.png", gradient: "linear-gradient(180deg, #efe38a 0%, #c4e08d 100%)" },
  Fall: { island: "/garden/fall_main_island.png", gradient: "linear-gradient(180deg, #efbf7f 0%, #dac7a3 100%)" },
  Winter: { island: "/garden/winter_main_island.png", gradient: "linear-gradient(180deg, #b9dff0 0%, #edf6f8 100%)" },
};

export default function GardenPage() {
  const [garden, setGarden] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    getGarden()
      .then(setGarden)
      .catch(setError)
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="loading-center">
        <LoadingSpinner size={48} />
      </div>
    );
  }

  if (error) {
    return (
      <div className="page-container">
        <Card>
          <CardContent>
            <div className="error-banner">Failed to load garden. Check that the backend is running.</div>
          </CardContent>
        </Card>
      </div>
    );
  }

  const season = getCurrentSeason();
  const bg = SEASON_BG[season];
  const grownCount = (garden.placedPlants || []).filter((plant) => plant.daysLeftTillFullyGrown <= 0).length;

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title page-title--serif">Your garden should feel earned.</h1>
                <div className="status-pill status-pill--warm">{season}</div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Value</div>
                  <div className="metric-value">{Math.round(garden.gardenValue)}</div>
                  <div className="metric-meta">garden</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Grown</div>
                  <div className="metric-value">{grownCount}</div>
                  <div className="metric-meta">plants</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="stats-grid">
          {[
            { label: "Plots", value: garden.numberOfOwnedPlots, meta: "claimed land" },
            { label: "Placed", value: (garden.placedPlants || []).length, meta: "currently planted" },
            { label: "Fertilizer", value: garden.fertilizerCount, meta: "growth boosts ready" },
            { label: "Season", value: season, meta: "active garden theme" },
          ].map((item) => (
            <Card key={item.label}>
              <CardContent>
                <div className="mini-stat">
                  <span className="metric-label">{item.label}</span>
                  <span className="mini-stat__value">{item.value}</span>
                  <span className="mini-stat__label">{item.meta}</span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        <div className="dashboard-grid dashboard-grid--two">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Garden Grid</CardTitle>
              </div>
            </CardHeader>
            <CardContent>
              <div
                style={{
                  position: "relative",
                  minHeight: 340,
                  borderRadius: 30,
                  overflow: "hidden",
                  padding: "1.2rem",
                  background: bg.gradient,
                }}
              >
                <img
                  src="/garden/clouds.png"
                  alt=""
                  style={{
                    position: "absolute",
                    inset: 0,
                    width: "100%",
                    height: "100%",
                    objectFit: "cover",
                    opacity: 0.35,
                    pointerEvents: "none",
                  }}
                />
                <img
                  src={bg.island}
                  alt={`${season} island`}
                  style={{
                    position: "absolute",
                    left: "50%",
                    bottom: "4%",
                    transform: "translateX(-50%)",
                    maxWidth: "82%",
                    maxHeight: "80%",
                    pointerEvents: "none",
                  }}
                />
                <div style={{ position: "relative", zIndex: 1, display: "grid", gap: "1rem", justifyItems: "center", minHeight: "100%" }}>
                  <div className="status-pill status-pill--warm">{season} season active</div>
                  {garden.placedPlants?.length === 0 && garden.numberOfOwnedPlots === 0 ? (
                    <div className="empty-state" style={{ maxWidth: 420 }}>
                      No plots yet.
                    </div>
                  ) : (
                    <GardenGrid
                      placedPlants={garden.placedPlants || []}
                      numberOfOwnedPlots={garden.numberOfOwnedPlots}
                    />
                  )}
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="stack">
            <Card variant="accent">
              <CardHeader>
                <div>
                  <CardTitle>Growth Snapshot</CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                <div className="list">
                  <div className="list-item">
                    <div className="list-item__copy">
                      <span className="list-item__title">Mature plants</span>
                      <span className="list-item__meta">{grownCount} ready</span>
                    </div>
                    <span className="status-pill">{grownCount}</span>
                  </div>
                  <div className="list-item">
                    <div className="list-item__copy">
                      <span className="list-item__title">Active placements</span>
                      <span className="list-item__meta">{(garden.placedPlants || []).length} on the island</span>
                    </div>
                    <span className="status-pill status-pill--warm">{(garden.placedPlants || []).length}</span>
                  </div>
                  <div className="list-item">
                    <div className="list-item__copy">
                      <span className="list-item__title">Support inventory</span>
                      <span className="list-item__meta">{garden.fertilizerCount} fertilizer</span>
                    </div>
                    <span className="status-pill">{garden.fertilizerCount}</span>
                  </div>
                </div>
              </CardContent>
            </Card>

            {garden.unplacedPlantsInventory && Object.keys(garden.unplacedPlantsInventory).length > 0 && (
              <Card variant="muted">
                <CardHeader>
                  <div>
                    <CardTitle>Unplaced Plants</CardTitle>
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="list">
                    {Object.entries(garden.unplacedPlantsInventory).map(([id, count]) => (
                      <div key={id} className="list-item">
                        <div className="list-item__copy">
                          <span className="list-item__title">{getPlantDisplayName(id)}</span>
                          <span className="list-item__meta">ready to place</span>
                        </div>
                        <span className="status-pill">{count}</span>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
