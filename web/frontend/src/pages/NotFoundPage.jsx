import { Link } from "react-router-dom";

export default function NotFoundPage() {
  return (
    <div className="page-container fade-in">
      <div className="loading-center" style={{ minHeight: "60vh", flexDirection: "column", gap: 16 }}>
        <h2 className="page-title" style={{ fontSize: "2rem" }}>Page Not Found</h2>
        <Link to="/dashboard" className="btn btn-primary">
          Go to Dashboard
        </Link>
      </div>
    </div>
  );
}
