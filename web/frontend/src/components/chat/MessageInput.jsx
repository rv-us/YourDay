import { useState } from "react";

export default function MessageInput({ onSend, disabled }) {
  const [text, setText] = useState("");

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!text.trim()) return;
    onSend(text.trim());
    setText("");
  };

  return (
    <form
      onSubmit={handleSubmit}
      style={{
        display: "flex",
        gap: 8,
        padding: "12px 16px",
        borderTop: "1px solid #C8DDB0",
        background: "white",
      }}
    >
      <input
        type="text"
        placeholder="Type a message..."
        value={text}
        onChange={(e) => setText(e.target.value)}
        disabled={disabled}
        style={{
          flex: 1,
          padding: "8px 14px",
          borderRadius: 20,
          border: "1px solid #C8DDB0",
          fontSize: 14,
          outline: "none",
        }}
      />
      <button
        type="submit"
        className="btn btn-primary"
        disabled={disabled || !text.trim()}
        style={{ borderRadius: 20, padding: "8px 20px" }}
      >
        Send
      </button>
    </form>
  );
}
