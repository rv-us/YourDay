import { useState, useEffect } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { getChatThreads } from "../api/chatApi";
import { useGroups } from "../hooks/useGroups";
import { createGroup } from "../api/groupsApi";
import { getFriends } from "../api/friendsApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";

function ThreadItem({ to, avatar, name, subtitle, timestamp, isGroup }) {
  return (
    <Link to={to}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          padding: "14px 18px",
          background: "white",
          transition: "background 0.1s",
          cursor: "pointer",
          borderBottom: "1px solid #F0F0F0",
        }}
        onMouseEnter={(e) => (e.currentTarget.style.background = "#F5F1E8")}
        onMouseLeave={(e) => (e.currentTarget.style.background = "white")}
      >
        <div
          style={{
            width: 44,
            height: 44,
            borderRadius: isGroup ? 10 : "50%",
            background: isGroup
              ? "linear-gradient(135deg, #7B1FA2, #CE93D8)"
              : "linear-gradient(135deg, #56AB2F, #A8E063)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            fontWeight: 700,
            fontSize: 16,
            marginRight: 12,
            flexShrink: 0,
          }}
        >
          {(avatar || "?")[0].toUpperCase()}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <span style={{ fontWeight: 600, fontSize: 14, color: "#1B2E0A" }}>{name}</span>
            {isGroup && (
              <span style={{ fontSize: 9, background: "#EDE7F6", color: "#7B1FA2", padding: "1px 5px", borderRadius: 6, fontWeight: 700 }}>
                GROUP
              </span>
            )}
          </div>
          <div style={{ fontSize: 12, color: "#5A7A3A", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {subtitle || "No messages yet"}
          </div>
        </div>
        {timestamp && (
          <div style={{ fontSize: 11, color: "#8FA87A", marginLeft: 8, flexShrink: 0 }}>
            {new Date(timestamp).toLocaleDateString()}
          </div>
        )}
      </div>
    </Link>
  );
}

export default function ChatListPage() {
  const { user } = useAuth();
  const [threads, setThreads] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [friends, setFriends] = useState([]);
  const [groupName, setGroupName] = useState("");
  const [selectedMembers, setSelectedMembers] = useState([]);
  const groups = useGroups(user?.uid);

  useEffect(() => {
    getChatThreads()
      .then(setThreads)
      .finally(() => setLoading(false));
    getFriends().then(setFriends).catch(() => {});
  }, []);

  const toggleMember = (userId) => {
    setSelectedMembers((prev) =>
      prev.includes(userId) ? prev.filter((id) => id !== userId) : [...prev, userId]
    );
  };

  const handleCreateGroup = async (e) => {
    e.preventDefault();
    if (!groupName.trim() || selectedMembers.length === 0) return;
    const memberDisplayNames = {};
    if (user?.uid) memberDisplayNames[user.uid] = user.displayName || user.email?.split("@")[0] || "";
    friends.filter((f) => selectedMembers.includes(f.userId)).forEach((f) => {
      memberDisplayNames[f.userId] = f.displayName;
    });
    await createGroup({
      name: groupName,
      memberIds: selectedMembers,
      memberDisplayNames,
    });
    setGroupName("");
    setSelectedMembers([]);
    setShowNewGroup(false);
  };

  return (
    <div className="page-container">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
        <h2 style={{ fontSize: 22, fontWeight: 800 }}>Messages</h2>
        <button className="btn btn-primary btn-sm" onClick={() => setShowNewGroup(!showNewGroup)}>
          + Group
        </button>
      </div>

      {/* New group form */}
      {showNewGroup && (
        <div className="card" style={{ marginBottom: 16 }}>
          <h3 className="section-title" style={{ marginBottom: 12 }}>New Group Chat</h3>
          <form onSubmit={handleCreateGroup} style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <input
              placeholder="Group name"
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              required
              style={{ padding: "8px 12px", borderRadius: 8, border: "1px solid #C8DDB0", fontSize: 13 }}
            />
            <div>
              <div style={{ fontSize: 12, color: "#5A7A3A", marginBottom: 6 }}>Select friends to add:</div>
              {friends.length === 0 ? (
                <p style={{ fontSize: 12, color: "#8FA87A" }}>No friends yet.</p>
              ) : (
                friends.map((f) => (
                  <label
                    key={f.userId}
                    style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6, cursor: "pointer", fontSize: 13 }}
                  >
                    <input
                      type="checkbox"
                      checked={selectedMembers.includes(f.userId)}
                      onChange={() => toggleMember(f.userId)}
                    />
                    {f.displayName}
                  </label>
                ))
              )}
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <button type="submit" className="btn btn-primary btn-sm">Create</button>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowNewGroup(false)}>Cancel</button>
            </div>
          </form>
        </div>
      )}

      {loading ? (
        <div className="loading-center"><LoadingSpinner /></div>
      ) : (
        <div className="card" style={{ padding: 0, overflow: "hidden" }}>
          {groups.map((group) => (
            <ThreadItem
              key={group.id}
              to={`/group/${group.id}`}
              avatar={group.name}
              name={group.name}
              subtitle={group.lastMessageText}
              timestamp={group.lastMessageAt?.toDate?.()?.toISOString() ?? group.lastMessageAt}
              isGroup
            />
          ))}
          {threads.map((thread) => (
            <ThreadItem
              key={thread.friendId}
              to={`/chat/${thread.friendId}`}
              avatar={thread.displayName}
              name={thread.displayName}
              subtitle={thread.lastMessage?.content}
              timestamp={thread.lastMessage?.timestamp}
              isGroup={false}
            />
          ))}
          {groups.length === 0 && threads.length === 0 && (
            <div style={{ padding: 20 }}>
              <p style={{ color: "#5A7A3A" }}>No conversations yet. Add friends to start chatting!</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
