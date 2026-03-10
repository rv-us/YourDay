import { useState, useEffect, useRef } from "react";
import { useParams, Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useGroupChat } from "../hooks/useGroupChat";
import { sendGroupMessage, getGroup, getGroupMembers, leaveGroup } from "../api/groupsApi";
import { getFriends } from "../api/friendsApi";
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
  const [displayName, setDisplayName] = useState("");
  const bottomRef = useRef(null);

  useEffect(() => {
    getGroup(groupId).then(setGroup).catch(() => {});
    getGroupMembers(groupId).then(setMembers).catch(() => {});
    // Get our own display name for sending messages
    getFriends().then(() => {}).catch(() => {});
    if (user?.displayName) setDisplayName(user.displayName);
  }, [groupId, user]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSend = async (content) => {
    setSending(true);
    try {
      await sendGroupMessage(groupId, content, displayName || user?.email?.split("@")[0] || "");
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
              borderRadius: 10,
              background: "linear-gradient(135deg, #7B1FA2, #CE93D8)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "white",
              fontWeight: 700,
              fontSize: 14,
            }}
          >
            {(group.name || "G")[0].toUpperCase()}
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: 15 }}>{group.name}</div>
            <div style={{ fontSize: 11, color: "#5A7A3A" }}>{(group.memberIds || []).length} members</div>
          </div>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <button className="btn btn-secondary btn-sm" onClick={() => setShowMembers(!showMembers)}>
            Members
          </button>
          <button className="btn btn-danger btn-sm" onClick={handleLeave}>
            Leave
          </button>
        </div>
      </div>

      {/* Members panel */}
      {showMembers && (
        <div
          style={{
            background: "#F5F1E8",
            borderBottom: "1px solid #C8DDB0",
            padding: "12px 16px",
            maxHeight: 200,
            overflowY: "auto",
          }}
        >
          <h4 style={{ fontWeight: 700, fontSize: 13, marginBottom: 8 }}>Members</h4>
          {members.map((m) => (
            <div
              key={m.id}
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "6px 0",
                fontSize: 13,
                borderBottom: "1px solid #E0E0E0",
              }}
            >
              <span>{m.displayName || m.id}</span>
              <span
                style={{
                  fontSize: 10,
                  fontWeight: 700,
                  color: m.role === "admin" ? "#FFA000" : "#5A7A3A",
                  background: m.role === "admin" ? "#FFF8E1" : "#E8F5E9",
                  padding: "2px 6px",
                  borderRadius: 8,
                }}
              >
                {m.role}
              </span>
            </div>
          ))}
        </div>
      )}

      {/* Messages */}
      <div style={{ flex: 1, overflowY: "auto", padding: 16, background: "#F5F1E8" }}>
        {messages.length === 0 && (
          <p style={{ textAlign: "center", color: "#8FA87A", fontSize: 13, marginTop: 40 }}>
            No messages yet. Start the conversation!
          </p>
        )}
        {messages.map((msg) => (
          <div key={msg.id}>
            {msg.senderId !== user?.uid && msg.senderDisplayName && (
              <div style={{ fontSize: 11, color: "#5A7A3A", marginBottom: 2, marginLeft: 4 }}>
                {msg.senderDisplayName}
              </div>
            )}
            <MessageBubble message={msg} isOwn={msg.senderId === user?.uid} />
          </div>
        ))}
        <div ref={bottomRef} />
      </div>

      <MessageInput onSend={handleSend} disabled={sending} />
    </div>
  );
}
