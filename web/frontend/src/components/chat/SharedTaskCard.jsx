import { acceptSharedTask, completeSharedTask, deleteSharedTask } from "../../api/sharedTasksApi";
import { useAuth } from "../../context/AuthContext";

export default function SharedTaskCard({ task, onUpdate }) {
  const { user } = useAuth();
  const isReceiver = task.receiverId === user?.uid;
  const isSender = task.senderId === user?.uid;

  const dueDate = task.dueDate?.toDate?.() ?? (task.dueDate ? new Date(task.dueDate) : null);

  return (
    <div
      style={{
        background: "white",
        border: `1px solid ${task.isCompleted ? "#C8E6C9" : "#C8DDB0"}`,
        borderRadius: 10,
        padding: "12px 14px",
        marginBottom: 8,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
        <div style={{ flex: 1 }}>
          <div
            style={{
              fontWeight: 600,
              fontSize: 14,
              textDecoration: task.isCompleted ? "line-through" : "none",
              color: task.isCompleted ? "#8FA87A" : "#1B2E0A",
            }}
          >
            {task.title}
          </div>
          {task.detail && (
            <div style={{ fontSize: 12, color: "#5A7A3A", marginTop: 2 }}>{task.detail}</div>
          )}
          {dueDate && (
            <div style={{ fontSize: 11, color: "#8FA87A", marginTop: 4 }}>
              Due: {dueDate.toLocaleDateString()}
            </div>
          )}
        </div>
        <div style={{ display: "flex", gap: 4, marginLeft: 8 }}>
          {isReceiver && !task.isAccepted && (
            <button
              className="btn btn-primary btn-sm"
              onClick={() => acceptSharedTask(task.id).then(onUpdate)}
            >
              Accept
            </button>
          )}
          {task.isAccepted && (
            <button
              className="btn btn-secondary btn-sm"
              onClick={() => completeSharedTask(task.id, !task.isCompleted).then(onUpdate)}
            >
              {task.isCompleted ? "Undo" : "Done"}
            </button>
          )}
          {(isSender || isReceiver) && (
            <button
              className="btn btn-danger btn-sm"
              onClick={() => deleteSharedTask(task.id).then(onUpdate)}
            >
              ✕
            </button>
          )}
        </div>
      </div>

      {/* Subtasks */}
      {task.subtasks?.length > 0 && (
        <div style={{ marginTop: 8, paddingLeft: 8 }}>
          {task.subtasks.map((st) => (
            <div
              key={st.id}
              style={{
                fontSize: 12,
                color: st.isDone ? "#8FA87A" : "#5A7A3A",
                textDecoration: st.isDone ? "line-through" : "none",
                marginBottom: 2,
              }}
            >
              {st.isDone ? "☑" : "☐"} {st.title}
            </div>
          ))}
        </div>
      )}

      {!task.isAccepted && isReceiver && (
        <div style={{ fontSize: 11, color: "#FFA000", marginTop: 6, fontWeight: 600 }}>
          Pending your acceptance
        </div>
      )}
      {!task.isAccepted && isSender && (
        <div style={{ fontSize: 11, color: "#8FA87A", marginTop: 6 }}>
          Waiting for acceptance...
        </div>
      )}
    </div>
  );
}
