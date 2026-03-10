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
        borderTop: "1px solid rgba(69, 90, 44, 0.08)",
        background: "rgba(255,255,255,0.78)",
      }}
    >
      <input
        type="text"
        placeholder="Message"
        value={text}
        onChange={(e) => setText(e.target.value)}
        disabled={disabled}
        style={{
          flex: 1,
          width: "auto",
          padding: "8px 14px",
          borderRadius: 20,
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
