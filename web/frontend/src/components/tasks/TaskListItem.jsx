import { useState } from "react";

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
    <div className="list-item" style={{ alignItems: "flex-start" }}>
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

      <div className="list-item__copy" style={{ flex: 1 }} onClick={() => setExpanded((value) => !value)}>
        <div className="compact-meta">
          <div
            className="list-item__title"
            style={{
              color: task.isDone ? "var(--text-muted)" : "var(--text-primary)",
              textDecoration: task.isDone ? "line-through" : "none",
              cursor: "pointer",
            }}
          >
            {task.title}
          </div>
          <span className="status-pill" style={{ background: `${meta.color}1f`, color: meta.color }}>
            {meta.label}
          </span>
          {task.isSharedPending && <span className="status-pill status-pill--warm">Pending</span>}
        </div>

        {task.detail && (
          <div
            className="list-item__meta"
            style={{
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

        {expanded && task.subtasks?.length > 0 && (
          <div className="list" style={{ marginTop: 8 }}>
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

      <div className="toolbar-actions" style={{ justifyContent: "flex-end" }}>
        {onMove && (
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={() => onMove(task.localTaskId, task.origin === "today" ? "master" : "today")}
          >
            Move
          </button>
        )}
        <button type="button" className="btn btn-danger btn-sm" onClick={() => onDelete(task.localTaskId)}>
          Delete
        </button>
      </div>
    </div>
  );
}
