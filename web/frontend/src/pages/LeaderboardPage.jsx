import { useState } from "react";
import { useLeaderboard } from "../hooks/useLeaderboard";
import { useAuth } from "../context/AuthContext";
import LeaderboardTable from "../components/leaderboard/LeaderboardTable";
import LoadingSpinner from "../components/shared/LoadingSpinner";

export default function LeaderboardPage() {
  const [mode, setMode] = useState("all"); // "all" | "friends"
  const { user } = useAuth();
  const { entries, loading, error, refetch } = useLeaderboard(mode);

  return (
    <div className="page-container">
      <div
        style={{
          background: "linear-gradient(135deg, #2E6B10 0%, #56AB2F 100%)",
          borderRadius: 20,
          padding: "20px 24px",
          color: "white",
          marginBottom: 20,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <div>
          <h2 style={{ fontSize: 22, fontWeight: 800 }}>Leaderboard</h2>
          <p style={{ fontSize: 13, opacity: 0.85 }}>{entries.length} players ranked</p>
        </div>
        <button
          onClick={refetch}
          style={{
            background: "rgba(255,255,255,0.2)",
            border: "1px solid rgba(255,255,255,0.4)",
            color: "white",
            padding: "6px 14px",
            borderRadius: 8,
            fontSize: 13,
            cursor: "pointer",
          }}
        >
          Refresh
        </button>
      </div>

      {/* Mode tabs */}
      <div
        style={{
          display: "flex",
          background: "#F5F1E8",
          borderRadius: 10,
          padding: 3,
          marginBottom: 16,
          maxWidth: 300,
        }}
      >
        {[["all", "All Players"], ["friends", "Friends Only"]].map(([m, label]) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            style={{
              flex: 1,
              padding: "8px 0",
              border: "none",
              borderRadius: 8,
              background: mode === m ? "white" : "transparent",
              fontWeight: mode === m ? 700 : 400,
              color: mode === m ? "#2E6B10" : "#5A7A3A",
              fontSize: 13,
              boxShadow: mode === m ? "0 1px 4px rgba(0,0,0,0.1)" : "none",
            }}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="card">
        {loading ? (
          <div className="loading-center">
            <LoadingSpinner />
          </div>
        ) : error ? (
          <p style={{ color: "#D32F2F", padding: 12 }}>Failed to load leaderboard.</p>
        ) : (
          <div>
            <LeaderboardTable entries={entries} currentUid={user?.uid} />
          </div>
        )}
      </div>
    </div>
  );
}
