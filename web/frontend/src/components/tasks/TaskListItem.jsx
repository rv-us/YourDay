import { useState } from "react";
import { Card, CardContent } from "../ui/card";

const ORIGIN_META = {
  today: { label: "Today", color: "var(--gold-500)" },
  master: { label: "Master", color: "var(--moss-600)" },
};

function formatDate(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export default function TaskListItem({ task, onToggle, onDelete, onMove }) {
  const [expanded, setExpanded] = useState(false);
  const meta = ORIGIN_META[task.origin] || ORIGIN_META.today;

  return (
    <Card variant={task.isDone ? "muted" : undefined}>
      <CardContent>
        <div style={{ display: "grid", gap: "0.95rem" }}>
          <div style={{ display: "flex", gap: "0.9rem", alignItems: "flex-start" }}>
            <button
              type="button"
              onClick={() => onToggle(task.localTaskId, !task.isDone)}
              aria-label={task.isDone ? "Mark task incomplete" : "Mark task complete"}
              style={{
                width: 32,
                height: 32,
                flexShrink: 0,
                display: "grid",
                placeItems: "center",
                borderRadius: "50%",
                border: `1px solid ${task.isDone ? "rgba(77,129,52,0.28)" : "rgba(77,129,52,0.16)"}`,
                background: task.isDone ? "rgba(118,166,81,0.14)" : "rgba(255,255,255,0.8)",
                boxShadow: "inset 0 1px 0 rgba(255,255,255,0.75)",
              }}
            >
              {task.isDone && (
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
                  <path d="M3 7.2L5.8 10L11 4.5" stroke="var(--moss-700)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>

            <div style={{ flex: 1, minWidth: 0 }} onClick={() => setExpanded((value) => !value)}>
              <div style={{ display: "flex", alignItems: "center", gap: "0.55rem", flexWrap: "wrap" }}>
                <h4
                  style={{
                    margin: 0,
                    fontSize: "1rem",
                    fontWeight: 700,
                    lineHeight: 1.35,
                    color: task.isDone ? "var(--text-muted)" : "var(--text-primary)",
                    textDecoration: task.isDone ? "line-through" : "none",
                    cursor: "pointer",
                  }}
                >
                  {task.title}
                </h4>
                <span
                  className="status-pill"
                  style={{ background: `${meta.color}1f`, color: meta.color }}
                >
                  {meta.label}
                </span>
                {task.isSharedPending && <span className="status-pill status-pill--warm">Pending</span>}
              </div>

              {(task.detail || task.dueDate) && (
                <div className="stack--sm" style={{ gap: "0.3rem", marginTop: "0.4rem" }}>
                  {task.detail && (
                    <div
                      className="list-item__meta"
                      style={{
                        maxWidth: "46rem",
                        whiteSpace: expanded ? "normal" : "nowrap",
                        overflow: expanded ? "visible" : "hidden",
                        textOverflow: expanded ? "clip" : "ellipsis",
                        textDecoration: task.isDone ? "line-through" : "none",
                        cursor: "pointer",
                      }}
                    >
                      {task.detail}
                    </div>
                  )}
                  {task.dueDate && <div className="list-item__meta">Due {formatDate(task.dueDate)}</div>}
                </div>
              )}
            </div>

            <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", justifyContent: "flex-end" }}>
              {onMove && (
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  onClick={() => onMove(task.localTaskId, task.origin === "today" ? "master" : "today")}
                >
                  Move to {task.origin === "today" ? "Master" : "Today"}
                </button>
              )}
              <button type="button" className="btn btn-danger btn-sm" onClick={() => onDelete(task.localTaskId)}>
                Delete
              </button>
            </div>
          </div>

          {expanded && task.subtasks?.length > 0 && (
            <div className="stack--sm" style={{ paddingLeft: "2.6rem" }}>
              {task.subtasks.map((subtask, index) => (
                <div key={subtask.id || index} className="list-item">
                  <div className="list-item__copy">
                    <span
                      className="list-item__title"
                      style={{
                        color: subtask.isDone ? "var(--text-muted)" : "var(--text-primary)",
                        textDecoration: subtask.isDone ? "line-through" : "none",
                      }}
                    >
                      {subtask.title}
                    </span>
                  </div>
                  <span className={`status-pill${subtask.isDone ? "" : " status-pill--warm"}`}>
                    {subtask.isDone ? "Done" : "Open"}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
