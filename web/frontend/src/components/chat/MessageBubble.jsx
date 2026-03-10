export default function MessageBubble({ message, isOwn }) {
  const ts = message.timestamp?.toDate?.() ?? (message.timestamp ? new Date(message.timestamp) : null);
  const timeStr = ts
    ? ts.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    : "";

  return (
    <div
      style={{
        display: "flex",
        justifyContent: isOwn ? "flex-end" : "flex-start",
        marginBottom: 6,
      }}
    >
      <div
        style={{
          maxWidth: "70%",
          padding: "10px 13px",
          borderRadius: isOwn ? "16px 16px 4px 16px" : "16px 16px 16px 4px",
          background: isOwn ? "linear-gradient(135deg, #315522, #67a347)" : "rgba(255,255,255,0.9)",
          color: isOwn ? "white" : "#1B2E0A",
          border: isOwn ? "none" : "1px solid rgba(69, 90, 44, 0.08)",
          boxShadow: "0 8px 18px rgba(0,0,0,0.06)",
        }}
      >
        <div style={{ fontSize: 14 }}>{message.content}</div>
        {timeStr && (
          <div
            style={{
              fontSize: 10,
              marginTop: 3,
              color: isOwn ? "rgba(255,255,255,0.7)" : "#8FA87A",
              textAlign: "right",
            }}
          >
            {timeStr}
          </div>
        )}
      </div>
    </div>
  );
}
