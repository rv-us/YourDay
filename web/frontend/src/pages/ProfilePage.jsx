import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { signOut } from "firebase/auth";
import { auth } from "../firebase";
import { usePlayerStats } from "../hooks/usePlayerStats";
import { useAuth } from "../context/AuthContext";
import XPBar from "../components/shared/XPBar";
import StatBadge from "../components/shared/StatBadge";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "../components/ui/card";

function xpForNextLevel(level) {
  if (level <= 0) return 100;
  if (level === 1) return 100;
  if (level === 2) return 300;
  if (level === 3) return 400;
  if (level === 4) return 500;
  const base = 300;
  return Math.round(base * Math.pow(2, level - 5));
}

export default function ProfilePage() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const { stats, loading, error } = usePlayerStats();
  const [showSignOutConfirm, setShowSignOutConfirm] = useState(false);

  const handleSignOut = async () => {
    await signOut(auth);
    navigate("/login");
  };

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
            <div className="error-banner">Failed to load profile. Check that the backend is running.</div>
          </CardContent>
        </Card>
      </div>
    );
  }

  const xpToNext = xpForNextLevel(stats.playerLevel);

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <span className="eyebrow">Player profile</span>
                <h1 className="page-title">{user?.displayName || user?.email?.split("@")[0] || "Gardener"}</h1>
                <p className="page-summary">{user?.email}</p>
                <XPBar currentXP={stats.currentXP} xpToNext={xpToNext} level={stats.playerLevel} />
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Total points</div>
                  <div className="metric-value">{Math.round(stats.totalPoints)}</div>
                  <div className="metric-meta">across all completed work</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">Garden value</div>
                  <div className="metric-value">{Math.round(stats.gardenValue)}</div>
                  <div className="metric-meta">current cultivated total</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="stats-grid">
          <StatBadge label="Level" value={stats.playerLevel} color="var(--moss-600)" />
          <StatBadge label="Total Points" value={Math.round(stats.totalPoints)} color="var(--gold-500)" />
          <StatBadge label="Plots Owned" value={stats.numberOfOwnedPlots} color="var(--moss-700)" />
          <StatBadge label="Fertilizer" value={stats.fertilizerCount} color="var(--moss-500)" />
        </div>

        <div className="dashboard-grid dashboard-grid--two">
          {stats.unplacedPlantsInventory && Object.keys(stats.unplacedPlantsInventory).length > 0 && (
            <Card variant="accent">
              <CardHeader>
                <div>
                  <span className="eyebrow">Inventory</span>
                  <CardTitle>Stored Plants</CardTitle>
                  <CardDescription>Blueprints and inventory that can still be placed into the garden.</CardDescription>
                </div>
              </CardHeader>
              <CardContent>
                <div className="list">
                  {Object.entries(stats.unplacedPlantsInventory).map(([blueprintId, count]) => (
                    <div key={blueprintId} className="list-item">
                      <div className="list-item__copy">
                        <span className="list-item__title">{blueprintId}</span>
                        <span className="list-item__meta">Available for the next planting session.</span>
                      </div>
                      <span className="status-pill">{count}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}

          <Card>
            <CardHeader>
              <div>
                <span className="eyebrow">Account</span>
                <CardTitle>Profile Settings</CardTitle>
                <CardDescription>Basic account details and session controls.</CardDescription>
              </div>
            </CardHeader>
            <CardContent>
              <div className="list">
                <div className="list-item">
                  <div className="list-item__copy">
                    <span className="list-item__title">Display name</span>
                    <span className="list-item__meta">{user?.displayName || "Not set"}</span>
                  </div>
                </div>
                <div className="list-item">
                  <div className="list-item__copy">
                    <span className="list-item__title">Email</span>
                    <span className="list-item__meta">{user?.email}</span>
                  </div>
                </div>
                {showSignOutConfirm ? (
                  <div className="error-banner">
                    <div className="stack--sm">
                      <span>Are you sure you want to sign out?</span>
                      <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                        <button className="btn btn-danger" onClick={handleSignOut}>
                          Sign Out
                        </button>
                        <button className="btn btn-secondary" onClick={() => setShowSignOutConfirm(false)}>
                          Cancel
                        </button>
                      </div>
                    </div>
                  </div>
                ) : (
                  <button className="btn btn-danger" onClick={() => setShowSignOutConfirm(true)}>
                    Sign Out
                  </button>
                )}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
