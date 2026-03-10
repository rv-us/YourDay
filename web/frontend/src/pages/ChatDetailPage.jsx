import { useState, useEffect, useRef } from "react";
import { useParams, Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useChat } from "../hooks/useChat";
import { useSharedTasks } from "../hooks/useSharedTasks";
import { sendMessage } from "../api/chatApi";
import { createSharedTask } from "../api/sharedTasksApi";
import { getFriends } from "../api/friendsApi";
import MessageBubble from "../components/chat/MessageBubble";
import MessageInput from "../components/chat/MessageInput";
import SharedTaskCard from "../components/chat/SharedTaskCard";
import LoadingSpinner from "../components/shared/LoadingSpinner";

export default function ChatDetailPage() {
  const { friendId } = useParams();
  const { user } = useAuth();
  const messages = useChat(friendId, user?.uid);
  const sharedTasks = useSharedTasks(friendId, user?.uid);
  const [friendName, setFriendName] = useState("");
  const [showTasks, setShowTasks] = useState(false);
  const [showNewTask, setShowNewTask] = useState(false);
  const [newTask, setNewTask] = useState({ title: "", detail: "", dueDate: "" });
  const [sending, setSending] = useState(false);
  const bottomRef = useRef(null);

  useEffect(() => {
    getFriends().then((friends) => {
      const f = friends.find((f) => f.userId === friendId);
      if (f) setFriendName(f.displayName);
    });
  }, [friendId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async (content) => {
    setSending(true);
    try {
      await sendMessage(friendId, content);
    } finally {
      setSending(false);
    }
  };

  const handleCreateTask = async (e) => {
    e.preventDefault();
    if (!newTask.title.trim()) return;
    await createSharedTask({
      receiverId: friendId,
      title: newTask.title,
      detail: newTask.detail,
      dueDate: newTask.dueDate || null,
      subtasks: [],
    });
    setNewTask({ title: "", detail: "", dueDate: "" });
    setShowNewTask(false);
  };

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "calc(100vh - 56px)",
        maxWidth: 700,
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: "12px 16px",
          background: "white",
          borderBottom: "1px solid #C8DDB0",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <Link to="/chat" style={{ color: "#56AB2F", fontSize: 20, fontWeight: 700 }}>←</Link>
          <div
            style={{
              width: 36,
              height: 36,
              borderRadius: "50%",
              background: "linear-gradient(135deg, #56AB2F, #A8E063)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "white",
              fontWeight: 700,
            }}
          >
            {(friendName || "?")[0].toUpperCase()}
          </div>
          <span style={{ fontWeight: 700, fontSize: 16 }}>{friendName || friendId}</span>
        </div>
        <button
          className="btn btn-secondary btn-sm"
          onClick={() => setShowTasks(!showTasks)}
        >
          Tasks {sharedTasks.length > 0 && `(${sharedTasks.length})`}
        </button>
      </div>

      {/* Shared tasks panel */}
      {showTasks && (
        <div
          style={{
            maxHeight: 300,
            overflowY: "auto",
            background: "#F5F1E8",
            borderBottom: "1px solid #C8DDB0",
            padding: "12px 16px",
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
            <h4 style={{ fontWeight: 700, fontSize: 14 }}>Shared Tasks</h4>
            <button
              className="btn btn-primary btn-sm"
              onClick={() => setShowNewTask(!showNewTask)}
            >
              + New Task
            </button>
          </div>

          {showNewTask && (
            <form onSubmit={handleCreateTask} style={{ marginBottom: 12 }}>
              <div style={{ display: "flex", flexDirection: "column", gap: 8, background: "white", padding: 12, borderRadius: 10, border: "1px solid #C8DDB0" }}>
                <input
                  placeholder="Task title *"
                  value={newTask.title}
                  onChange={(e) => setNewTask({ ...newTask, title: e.target.value })}
                  required
                  style={{ padding: "8px 12px", borderRadius: 8, border: "1px solid #C8DDB0", fontSize: 13 }}
                />
                <input
                  placeholder="Details (optional)"
                  value={newTask.detail}
                  onChange={(e) => setNewTask({ ...newTask, detail: e.target.value })}
                  style={{ padding: "8px 12px", borderRadius: 8, border: "1px solid #C8DDB0", fontSize: 13 }}
                />
                <input
                  type="date"
                  value={newTask.dueDate}
                  onChange={(e) => setNewTask({ ...newTask, dueDate: e.target.value })}
                  style={{ padding: "8px 12px", borderRadius: 8, border: "1px solid #C8DDB0", fontSize: 13 }}
                />
                <div style={{ display: "flex", gap: 8 }}>
                  <button type="submit" className="btn btn-primary btn-sm">Send Task</button>
                  <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowNewTask(false)}>Cancel</button>
                </div>
              </div>
            </form>
          )}

          {sharedTasks.length === 0 ? (
            <p style={{ fontSize: 13, color: "#5A7A3A" }}>No shared tasks yet.</p>
          ) : (
            sharedTasks.map((task) => (
              <SharedTaskCard
                key={task.id}
                task={task}
                onUpdate={() => {}}
              />
            ))
          )}
        </div>
      )}

      {/* Messages */}
      <div
        style={{
          flex: 1,
          overflowY: "auto",
          padding: "16px",
          background: "#F5F1E8",
        }}
      >
        {messages.length === 0 && (
          <p style={{ textAlign: "center", color: "#8FA87A", fontSize: 13, marginTop: 40 }}>
            No messages yet. Say hi!
          </p>
        )}
        {messages.map((msg) => (
          <MessageBubble key={msg.id} message={msg} isOwn={msg.senderId === user?.uid} />
        ))}
        <div ref={bottomRef} />
      </div>

      <MessageInput onSend={handleSend} disabled={sending} />
    </div>
  );
}
