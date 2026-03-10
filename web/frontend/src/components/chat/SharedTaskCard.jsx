import { acceptSharedTask, completeSharedTask, deleteSharedTask } from "../../api/sharedTasksApi";
import { useAuth } from "../../context/AuthContext";

export default function SharedTaskCard({ task, onUpdate }) {
  const { user } = useAuth();
  const isReceiver = task.receiverId === user?.uid;
  const isSender = task.senderId === user?.uid;
  const dueDate = task.dueDate?.toDate?.() ?? (task.dueDate ? new Date(task.dueDate) : null);

  return (
    <div className="list-item">
      <div className="list-item__copy">
        <div
          className="list-item__title"
          style={{
            textDecoration: task.isCompleted ? "line-through" : "none",
            color: task.isCompleted ? "var(--text-muted)" : "var(--text-primary)",
          }}
        >
          {task.title}
        </div>
        {task.detail && <div className="list-item__meta">{task.detail}</div>}
        {dueDate && <div className="list-item__meta">Due {dueDate.toLocaleDateString()}</div>}
        {!task.isAccepted && (
          <div className="list-item__meta">
            {isReceiver ? "Waiting for acceptance" : "Pending"}
          </div>
        )}
      </div>

      <div className="toolbar-actions">
        {isReceiver && !task.isAccepted && (
          <button className="btn btn-primary btn-sm" onClick={() => acceptSharedTask(task.id).then(onUpdate)}>
            Accept
          </button>
        )}
        {task.isAccepted && (
          <button className="btn btn-secondary btn-sm" onClick={() => completeSharedTask(task.id, !task.isCompleted).then(onUpdate)}>
            {task.isCompleted ? "Undo" : "Done"}
          </button>
        )}
        {(isSender || isReceiver) && (
          <button className="btn btn-danger btn-sm" onClick={() => deleteSharedTask(task.id).then(onUpdate)}>
            Delete
          </button>
        )}
      </div>
    </div>
  );
}
