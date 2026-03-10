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
      const friend = friends.find((item) => item.userId === friendId);
      if (friend) setFriendName(friend.displayName);
    });
  }, [friendId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, showTasks]);

  const handleSend = async (content) => {
    setSending(true);
    try {
      await sendMessage(friendId, content);
    } finally {
      setSending(false);
    }
  };

  const handleCreateTask = async (event) => {
    event.preventDefault();
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
    <div className="chat-shell fade-in">
      <div className="chat-frame">
        <div className="chat-header">
          <div className="chat-header__title">
            <Link to="/chat" className="btn btn-ghost btn-sm">Back</Link>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: "50%",
                background: "linear-gradient(135deg, #56AB2F, #A8E063)",
                display: "grid",
                placeItems: "center",
                color: "white",
                fontWeight: 700,
                flexShrink: 0,
              }}
            >
              {(friendName || "?")[0].toUpperCase()}
            </div>
            <div className="list-item__copy">
              <div className="list-item__title">{friendName || friendId}</div>
            </div>
          </div>

          <button className="btn btn-secondary btn-sm" onClick={() => setShowTasks((value) => !value)}>
            Tasks {sharedTasks.length > 0 ? `(${sharedTasks.length})` : ""}
          </button>
        </div>

        {showTasks && (
          <div className="chat-sidebar">
            <div className="stack">
              <div className="toolbar-actions" style={{ justifyContent: "space-between" }}>
                <div className="section-title">Shared Tasks</div>
                <button className="btn btn-primary btn-sm" onClick={() => setShowNewTask((value) => !value)}>
                  {showNewTask ? "Close" : "New Task"}
                </button>
              </div>

              {showNewTask && (
                <form onSubmit={handleCreateTask} className="stack">
                  <input
                    placeholder="Task title"
                    value={newTask.title}
                    onChange={(event) => setNewTask({ ...newTask, title: event.target.value })}
                    required
                  />
                  <input
                    placeholder="Details"
                    value={newTask.detail}
                    onChange={(event) => setNewTask({ ...newTask, detail: event.target.value })}
                  />
                  <input
                    type="date"
                    value={newTask.dueDate}
                    onChange={(event) => setNewTask({ ...newTask, dueDate: event.target.value })}
                  />
                  <div className="toolbar-actions">
                    <button type="submit" className="btn btn-primary btn-sm">Send</button>
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowNewTask(false)}>Cancel</button>
                  </div>
                </form>
              )}

              {sharedTasks.length === 0 ? (
                <div className="empty-state">No shared tasks.</div>
              ) : (
                <div className="list">
                  {sharedTasks.map((task) => (
                    <SharedTaskCard key={task.id} task={task} onUpdate={() => {}} />
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        <div className="chat-body">
          {messages.length === 0 ? (
            <p className="list-item__meta" style={{ textAlign: "center", marginTop: 40 }}>
              No messages yet.
            </p>
          ) : (
            messages.map((message) => (
              <MessageBubble key={message.id} message={message} isOwn={message.senderId === user?.uid} />
            ))
          )}
          <div ref={bottomRef} />
        </div>

        <MessageInput onSend={handleSend} disabled={sending} />
      </div>
    </div>
  );
}
