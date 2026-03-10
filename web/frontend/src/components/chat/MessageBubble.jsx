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
          padding: "8px 12px",
          borderRadius: isOwn ? "16px 16px 4px 16px" : "16px 16px 16px 4px",
          background: isOwn ? "#56AB2F" : "white",
          color: isOwn ? "white" : "#1B2E0A",
          border: isOwn ? "none" : "1px solid #C8DDB0",
          boxShadow: "0 1px 3px rgba(0,0,0,0.08)",
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
