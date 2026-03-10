import { useState, useEffect } from "react";
import { getJournalEntries } from "../api/journalApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";

const STATUS_COLORS = {
  completed: { bg: "#E8F5E9", color: "#2E7D32", label: "Completed" },
  partial:   { bg: "#FFF8E1", color: "#F57F17", label: "Partial" },
  notStarted:{ bg: "#FFEBEE", color: "#C62828", label: "Not Started" },
};

function formatTime(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function formatDate(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

export default function JournalPage() {
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(null);

  useEffect(() => {
    getJournalEntries()
      .then(setEntries)
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="page-container">
      <div
        style={{
          background: "linear-gradient(135deg, #4A148C 0%, #7B1FA2 100%)",
          borderRadius: 20,
          padding: "20px 24px",
          color: "white",
          marginBottom: 20,
        }}
      >
        <h2 style={{ fontSize: 22, fontWeight: 800 }}>Journal</h2>
        <p style={{ fontSize: 13, opacity: 0.85 }}>{entries.length} entries</p>
      </div>

      {loading ? (
        <div className="loading-center"><LoadingSpinner /></div>
      ) : entries.length === 0 ? (
        <div className="card">
          <p style={{ color: "#5A7A3A" }}>No journal entries yet. Complete scheduled tasks in the iOS app to create entries.</p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {entries.map((entry) => {
            const status = STATUS_COLORS[entry.completionStatus] || STATUS_COLORS.completed;
            const isExp = expanded === entry.id;
            return (
              <div
                key={entry.id}
                className="card"
                style={{ cursor: "pointer", borderLeft: `4px solid ${status.color}` }}
                onClick={() => setExpanded(isExp ? null : entry.id)}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 2 }}>{entry.taskTitle}</div>
                    <div style={{ fontSize: 12, color: "#5A7A3A" }}>
                      {formatDate(entry.scheduledStartTime)} · {formatTime(entry.scheduledStartTime)} – {formatTime(entry.scheduledEndTime)}
                    </div>
                  </div>
                  <span
                    style={{
                      background: status.bg,
                      color: status.color,
                      fontSize: 11,
                      fontWeight: 700,
                      padding: "2px 8px",
                      borderRadius: 10,
                      marginLeft: 8,
                      flexShrink: 0,
                    }}
                  >
                    {status.label}
                  </span>
                </div>

                {isExp && (
                  <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 8 }}>
                    {[
                      { label: "What I did", value: entry.whatDid },
                      { label: "How it went", value: entry.howWent },
                      { label: "What I learned", value: entry.learned },
                      { label: "Distractions", value: entry.distractions },
                    ].filter(({ value }) => value).map(({ label, value }) => (
                      <div key={label} style={{ background: "#F5F1E8", borderRadius: 8, padding: "8px 12px" }}>
                        <div style={{ fontSize: 11, color: "#5A7A3A", fontWeight: 600, marginBottom: 2 }}>{label}</div>
                        <div style={{ fontSize: 13, color: "#1B2E0A", whiteSpace: "pre-wrap" }}>{value}</div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
