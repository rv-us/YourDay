import { useState } from "react";

export default function NewTaskModal({ origin: initialOrigin = "today", onSave, onClose }) {
  const [title, setTitle] = useState("");
  const [detail, setDetail] = useState("");
  const [dueDate, setDueDate] = useState(new Date().toISOString().split("T")[0]);
  const [origin, setOrigin] = useState(initialOrigin);
  const [subtasks, setSubtasks] = useState([]);
  const [newSubtask, setNewSubtask] = useState("");
  const [saving, setSaving] = useState(false);

  const handleAddSubtask = () => {
    if (!newSubtask.trim()) return;
    setSubtasks((current) => [...current, { title: newSubtask.trim(), isDone: false }]);
    setNewSubtask("");
  };

  const handleRemoveSubtask = (index) => {
    setSubtasks((current) => current.filter((_, itemIndex) => itemIndex !== index));
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    if (!title.trim()) return;
    setSaving(true);
    try {
      await onSave({
        title: title.trim(),
        detail: detail.trim(),
        dueDate: new Date(dueDate).toISOString(),
        origin,
        subtasks,
      });
      onClose();
    } catch {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay" onClick={(event) => event.target === event.currentTarget && onClose()}>
      <div className="modal-panel">
        <div className="stack">
          <div className="stack--sm">
            <span className="eyebrow">New task</span>
            <h2 className="page-title" style={{ fontSize: "1.8rem" }}>
              Plant a clean work item.
            </h2>
            <p className="page-summary">
              Capture a clear title, put it in the right board, and optionally break it into subtasks before it lands.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="stack">
            <div className="segmented-control">
              {["today", "master"].map((value) => (
                <button
                  key={value}
                  type="button"
                  className={`segmented-control__button${origin === value ? " segmented-control__button--active" : ""}`}
                  onClick={() => setOrigin(value)}
                >
                  {value === "today" ? "Today" : "Master List"}
                </button>
              ))}
            </div>

            <div className="form-field">
              <label className="form-label">Title</label>
              <input
                type="text"
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                required
                placeholder="Ship analytics cleanup"
              />
            </div>

            <div className="form-field">
              <label className="form-label">Details</label>
              <textarea
                value={detail}
                onChange={(event) => setDetail(event.target.value)}
                rows={4}
                placeholder="Scope, notes, or acceptance criteria"
              />
            </div>

            <div className="form-field">
              <label className="form-label">Due Date</label>
              <input type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} />
            </div>

            <div className="form-field">
              <label className="form-label">Subtasks</label>
              {subtasks.length > 0 && (
                <div className="list">
                  {subtasks.map((subtask, index) => (
                    <div key={`${subtask.title}-${index}`} className="list-item">
                      <div className="list-item__copy">
                        <span className="list-item__title">{subtask.title}</span>
                      </div>
                      <button type="button" className="btn btn-danger btn-sm" onClick={() => handleRemoveSubtask(index)}>
                        Remove
                      </button>
                    </div>
                  ))}
                </div>
              )}
              <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                <input
                  type="text"
                  value={newSubtask}
                  onChange={(event) => setNewSubtask(event.target.value)}
                  placeholder="Add a subtask"
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      handleAddSubtask();
                    }
                  }}
                />
                <button type="button" className="btn btn-secondary" onClick={handleAddSubtask}>
                  Add subtask
                </button>
              </div>
            </div>

            <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
              <button type="submit" className="btn btn-primary" disabled={saving || !title.trim()}>
                {saving ? "Saving..." : "Create Task"}
              </button>
              <button type="button" className="btn btn-ghost" onClick={onClose}>
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
