import { Link } from "react-router-dom";

export default function NotFoundPage() {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        height: "calc(100vh - 56px)",
        gap: 16,
      }}
    >
      <div style={{ fontSize: 64 }}>🌵</div>
      <h2 style={{ fontSize: 24, fontWeight: 800 }}>Page Not Found</h2>
      <Link to="/garden">
        <button className="btn btn-primary">Go to Garden</button>
      </Link>
    </div>
  );
}
