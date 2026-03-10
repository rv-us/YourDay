import { useState, useEffect } from "react";
import { getJournalEntries } from "../api/journalApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent } from "../components/ui/card";

const STATUS_META = {
  completed: { className: "", label: "Completed" },
  partial: { className: " status-pill--warm", label: "Partial" },
  notStarted: { className: " status-pill--danger", label: "Not Started" },
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
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Journal</h1>
              </div>
              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Entries</div>
                  <div className="metric-value">{entries.length}</div>
                  <div className="metric-meta">recorded</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {loading ? (
          <div className="loading-center"><LoadingSpinner /></div>
        ) : entries.length === 0 ? (
          <Card>
            <CardContent>
              <div className="empty-state">No journal entries yet.</div>
            </CardContent>
          </Card>
        ) : (
          <div className="list">
            {entries.map((entry) => {
              const status = STATUS_META[entry.completionStatus] || STATUS_META.completed;
              const isExpanded = expanded === entry.id;

              return (
                <Card key={entry.id}>
                  <CardContent>
                    <div className="stack--sm">
                      <button
                        type="button"
                        className="list-item"
                        onClick={() => setExpanded(isExpanded ? null : entry.id)}
                        style={{ width: "100%", textAlign: "left", border: "1px solid rgba(69, 90, 44, 0.08)" }}
                      >
                        <div className="list-item__copy">
                          <div className="list-item__title">{entry.taskTitle}</div>
                          <div className="list-item__meta">
                            {formatDate(entry.scheduledStartTime)} · {formatTime(entry.scheduledStartTime)} - {formatTime(entry.scheduledEndTime)}
                          </div>
                        </div>
                        <span className={`status-pill${status.className}`}>{status.label}</span>
                      </button>

                      {isExpanded && (
                        <div className="list">
                          {[
                            { label: "What I did", value: entry.whatDid },
                            { label: "How it went", value: entry.howWent },
                            { label: "What I learned", value: entry.learned },
                            { label: "Distractions", value: entry.distractions },
                          ].filter(({ value }) => value).map(({ label, value }) => (
                            <div key={label} className="list-item" style={{ alignItems: "flex-start" }}>
                              <div className="list-item__copy">
                                <div className="list-item__title">{label}</div>
                                <div className="list-item__meta" style={{ whiteSpace: "pre-wrap" }}>{value}</div>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
