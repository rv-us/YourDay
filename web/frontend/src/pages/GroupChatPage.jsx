import { useState, useEffect, useRef } from "react";
import { useParams, Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useGroupChat } from "../hooks/useGroupChat";
import { sendGroupMessage, getGroup, getGroupMembers, leaveGroup } from "../api/groupsApi";
import MessageBubble from "../components/chat/MessageBubble";
import MessageInput from "../components/chat/MessageInput";
import LoadingSpinner from "../components/shared/LoadingSpinner";

export default function GroupChatPage() {
  const { groupId } = useParams();
  const { user } = useAuth();
  const messages = useGroupChat(groupId);
  const [group, setGroup] = useState(null);
  const [members, setMembers] = useState([]);
  const [showMembers, setShowMembers] = useState(false);
  const [sending, setSending] = useState(false);
  const bottomRef = useRef(null);

  useEffect(() => {
    getGroup(groupId).then(setGroup).catch(() => {});
    getGroupMembers(groupId).then(setMembers).catch(() => {});
  }, [groupId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, showMembers]);

  const handleSend = async (content) => {
    setSending(true);
    try {
      await sendGroupMessage(groupId, content, user?.displayName || user?.email?.split("@")[0] || "");
    } finally {
      setSending(false);
    }
  };

  const handleLeave = async () => {
    if (!confirm("Leave this group?")) return;
    await leaveGroup(groupId);
    window.location.href = "/chat";
  };

  if (!group) {
    return (
      <div className="loading-center" style={{ height: "calc(100vh - 56px)" }}>
        <LoadingSpinner size={48} />
      </div>
    );
  }

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
                borderRadius: 14,
                background: "linear-gradient(135deg, #7B1FA2, #CE93D8)",
                display: "grid",
                placeItems: "center",
                color: "white",
                fontWeight: 700,
                flexShrink: 0,
              }}
            >
              {(group.name || "G")[0].toUpperCase()}
            </div>
            <div className="list-item__copy">
              <div className="list-item__title">{group.name}</div>
              <div className="list-item__meta">{(group.memberIds || []).length} members</div>
            </div>
          </div>

          <div className="toolbar-actions">
            <button className="btn btn-secondary btn-sm" onClick={() => setShowMembers((value) => !value)}>
              Members
            </button>
            <button className="btn btn-danger btn-sm" onClick={handleLeave}>
              Leave
            </button>
          </div>
        </div>

        {showMembers && (
          <div className="chat-sidebar">
            <div className="list">
              {members.map((member) => (
                <div key={member.id} className="list-item">
                  <div className="list-item__copy">
                    <div className="list-item__title">{member.displayName || member.id}</div>
                  </div>
                  <span className={`status-pill${member.role === "admin" ? " status-pill--warm" : ""}`}>
                    {member.role}
                  </span>
                </div>
              ))}
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
              <div key={message.id}>
                {message.senderId !== user?.uid && message.senderDisplayName && (
                  <div className="list-item__meta" style={{ marginBottom: 4, marginLeft: 4 }}>
                    {message.senderDisplayName}
                  </div>
                )}
                <MessageBubble message={message} isOwn={message.senderId === user?.uid} />
              </div>
            ))
          )}
          <div ref={bottomRef} />
        </div>

        <MessageInput onSend={handleSend} disabled={sending} />
      </div>
    </div>
  );
}
