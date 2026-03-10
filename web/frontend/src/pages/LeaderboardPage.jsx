import { useState } from "react";
import { useLeaderboard } from "../hooks/useLeaderboard";
import { useAuth } from "../context/AuthContext";
import LeaderboardTable from "../components/leaderboard/LeaderboardTable";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent } from "../components/ui/card";

export default function LeaderboardPage() {
  const [mode, setMode] = useState("all");
  const { user } = useAuth();
  const { entries, loading, error, refetch } = useLeaderboard(mode);

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Leaderboard</h1>
                <div className="toolbar-actions">
                  <button className="btn btn-secondary btn-sm" onClick={refetch}>Refresh</button>
                  <div className="segmented-control">
                    {[["all", "All"], ["friends", "Friends"]].map(([value, label]) => (
                      <button
                        key={value}
                        type="button"
                        className={`segmented-control__button${mode === value ? " segmented-control__button--active" : ""}`}
                        onClick={() => setMode(value)}
                      >
                        {label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Players</div>
                  <div className="metric-value">{entries.length}</div>
                  <div className="metric-meta">ranked</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent>
            {loading ? (
              <div className="loading-center">
                <LoadingSpinner />
              </div>
            ) : error ? (
              <div className="error-banner">Failed to load leaderboard.</div>
            ) : (
              <LeaderboardTable entries={entries} currentUid={user?.uid} />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
