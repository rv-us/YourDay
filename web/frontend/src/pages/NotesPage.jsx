import { useEffect, useState } from "react";
import { getNotes, saveNote, deleteNote } from "../api/notesApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card";

function formatDate(iso) {
  if (!iso) return "Undated";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function NotesPage() {
  const [notes, setNotes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(null);
  const [editingId, setEditingId] = useState(null);
  const [editContent, setEditContent] = useState("");
  const [showNewNote, setShowNewNote] = useState(false);
  const [newContent, setNewContent] = useState("");
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    getNotes()
      .then(setNotes)
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, []);

  const handleDelete = async (noteId) => {
    if (!confirm("Delete this note?")) return;
    await deleteNote(noteId);
    load();
  };

  const handleCreateNote = async () => {
    if (!newContent.trim()) return;
    setSaving(true);
    try {
      await saveNote({ content: newContent.trim() });
      setNewContent("");
      setShowNewNote(false);
      load();
    } finally {
      setSaving(false);
    }
  };

  const handleEditNote = async (noteId) => {
    if (!editContent.trim()) return;
    setSaving(true);
    try {
      await saveNote({ localNoteId: noteId, content: editContent.trim() });
      setEditingId(null);
      load();
    } finally {
      setSaving(false);
    }
  };

  const startEdit = (note) => {
    setEditingId(note.localNoteId || note.id);
    setEditContent(note.content || "");
    setExpanded(null);
  };

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Notes</h1>
                <div className="toolbar-actions">
                  <button className="btn btn-secondary" onClick={() => setShowNewNote(true)}>
                    New Note
                  </button>
                  <button className="btn btn-ghost" onClick={load} style={{ color: "#f8f5ee", borderColor: "rgba(255,255,255,0.16)" }}>
                    Refresh
                  </button>
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Count</div>
                  <div className="metric-value">{notes.length}</div>
                  <div className="metric-meta">saved</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">State</div>
                  <div className="metric-value" style={{ fontSize: "1.15rem" }}>
                    {notes.length ? "Organized" : "Empty"}
                  </div>
                  <div className="metric-meta">workspace</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {showNewNote && (
          <Card variant="accent">
            <CardHeader>
              <div>
                <CardTitle>New Note</CardTitle>
              </div>
            </CardHeader>
            <CardContent>
              <div className="stack">
                <textarea
                  value={newContent}
                  onChange={(event) => setNewContent(event.target.value)}
                  placeholder="Write your note..."
                  rows={5}
                />
                <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                  <button className="btn btn-primary" onClick={handleCreateNote} disabled={saving || !newContent.trim()}>
                    {saving ? "Saving..." : "Save Note"}
                  </button>
                  <button
                    className="btn btn-secondary"
                    onClick={() => {
                      setShowNewNote(false);
                      setNewContent("");
                    }}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        {loading ? (
          <div className="loading-center">
            <LoadingSpinner />
          </div>
        ) : notes.length === 0 ? (
          <Card>
            <CardContent>
              <div className="empty-state">No notes yet.</div>
            </CardContent>
          </Card>
        ) : (
          <div className="stack">
            {notes.map((note) => {
              const noteId = note.localNoteId || note.id;
              const isEditing = editingId === noteId;
              const isExpanded = expanded === noteId;
              const preview = note.content?.slice(0, 180) || "";

              if (isEditing) {
                return (
                  <Card key={noteId} variant="accent">
                    <CardContent>
                      <div className="stack">
                        <textarea
                          value={editContent}
                          onChange={(event) => setEditContent(event.target.value)}
                          rows={6}
                          autoFocus
                        />
                        <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                          <button className="btn btn-primary" onClick={() => handleEditNote(noteId)} disabled={saving}>
                            {saving ? "Saving..." : "Save"}
                          </button>
                          <button className="btn btn-secondary" onClick={() => setEditingId(null)}>
                            Cancel
                          </button>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                );
              }

              return (
                <Card key={noteId}>
                  <CardContent>
                    <div className="stack--sm">
                      <div style={{ display: "flex", justifyContent: "space-between", gap: "1rem", alignItems: "flex-start", flexWrap: "wrap" }}>
                        <div className="stack--sm" style={{ gap: "0.35rem", flex: 1 }}>
                          <span className="eyebrow">{formatDate(note.createdAt)}</span>
                          <div
                            className="list-item__title"
                            style={{ cursor: "pointer", whiteSpace: isExpanded ? "pre-wrap" : "normal" }}
                            onClick={() => setExpanded(isExpanded ? null : noteId)}
                          >
                            {isExpanded ? note.content : preview}
                            {!isExpanded && note.content?.length > 180 ? "..." : ""}
                          </div>
                        </div>

                        <div style={{ display: "flex", gap: "0.65rem", flexWrap: "wrap" }}>
                          <button className="btn btn-secondary btn-sm" onClick={() => startEdit(note)}>
                            Edit
                          </button>
                          <button className="btn btn-danger btn-sm" onClick={() => handleDelete(noteId)}>
                            Delete
                          </button>
                        </div>
                      </div>
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
